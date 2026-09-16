#if DEBUG
import Foundation
import UIKit
import OSLog

/// DEBUG-only on-device probe for Apple Intelligence vision.
///
/// The catalog advertises capability; `RuntimeProfiles.json` records what is
/// *verified*. This produces the evidence before `verifiedVision` is flipped:
///
///     xcrun devicectl device process launch --console --device <udid> \
///       com.vinothrajalingam.EdgeMindAi -probe-fm-vision
enum AppleFoundationVisionProbe {
    static func runIfRequested() async {
        // Triggered by a launch argument or the FM_VISION_PROBE environment
        // variable (devicectl intercepts dash-prefixed arguments, so env is the
        // reliable channel):
        //   DEVICECTL_CHILD_FM_VISION_PROBE=1 xcrun devicectl device process launch --console ...
        let environment = ProcessInfo.processInfo.environment
        let visionRequested = ProcessInfo.processInfo.arguments.contains("-probe-fm-vision")
            || environment["FM_VISION_PROBE"] == "1"
        let toolRequested = environment["FM_TOOL_PROBE"] == "1"
        let documentRequested = environment["DOC_PROBE"] == "1"

        if documentRequested { await runDocumentProbe() }
        if toolRequested { await runToolCallingProbe() }
        guard visionRequested else { return }

        print("FMPROBE supportsVision=\(AppleFoundationModelService.supportsVision)")
        print("FMPROBE supportsToolCalling=\(AppleFoundationModelService.supportsToolCalling)")

        guard AppleFoundationModelService.supportsVision else {
            print("FMPROBE RESULT: SKIPPED (system model reports no vision capability)")
            return
        }
        guard AppleFoundationModelService.availabilityMessage == nil else {
            print("FMPROBE RESULT: SKIPPED (\(AppleFoundationModelService.availabilityMessage ?? ""))")
            return
        }
        guard let item = MockCatalogData.items.first(where: { $0.runtimeType == .foundationModels }) else {
            print("FMPROBE RESULT: SKIPPED (no Foundation Models catalog entry)")
            return
        }

        let word = "PLATYPUS"
        guard let image = probeImage(word: word), let data = image.jpegData(compressionQuality: 0.95) else {
            print("FMPROBE RESULT: ERROR could not render probe image")
            return
        }

        let model = InstalledModel(
            catalogItem: item,
            installState: .installed,
            progress: 1,
            localPath: AppleFoundationModelService.localPathMarker
        )

        do {
            let reply = try await AppleFoundationInferenceService().generateReply(
                prompt: "What single word is written in this image? Reply with only that word.",
                model: model,
                conversation: [],
                searchContext: nil,
                systemPrompt: "You read text in images accurately and answer in one word.",
                imageData: data
            )
            let answer = reply.text
            let passed = answer.uppercased().contains(word)
            print("FMPROBE RESULT: \(passed ? "PASS" : "FAIL") expected=\(word) got=\(answer)")
        } catch {
            print("FMPROBE RESULT: ERROR \(error.localizedDescription)")
        }
    }

    /// Checks whether the system model follows this app's existing
    /// `<tool_call>` convention, which would let it reuse the whole agentic
    /// loop unchanged instead of needing a second, native tool path.
    private static func runToolCallingProbe() async {
        print("FMPROBE supportsToolCalling=\(AppleFoundationModelService.supportsToolCalling)")

        guard AppleFoundationModelService.supportsToolCalling else {
            print("FMPROBE TOOL RESULT: SKIPPED (no toolCalling capability)")
            return
        }
        guard let item = MockCatalogData.items.first(where: { $0.runtimeType == .foundationModels }),
              AppleFoundationModelService.availabilityMessage == nil else {
            print("FMPROBE TOOL RESULT: SKIPPED (model unavailable)")
            return
        }

        let toolsSection = ToolRegistry.renderPromptSection(for: [CalculateTool(), GetCurrentTimeTool()])

        let model = InstalledModel(
            catalogItem: item,
            installState: .installed,
            progress: 1,
            localPath: AppleFoundationModelService.localPathMarker
        )

        do {
            let reply = try await AppleFoundationInferenceService().generateReply(
                prompt: "What is 47 * 89? Use the calculate tool.",
                model: model,
                conversation: [],
                searchContext: nil,
                systemPrompt: "You are a helpful assistant." + toolsSection,
                imageData: nil
            )
            let text = reply.text
            let lowered = text.lowercased()
            let hasToolCall = lowered.contains("<tool_call>")
            let hasAnswer = text.contains("4183") // 47 * 89
            print("FMPROBE TOOL RESULT: \(hasToolCall ? "EMITTED_TOOL_CALL" : "NO_TOOL_CALL") computedAnswer=\(hasAnswer)")
            print("FMPROBE TOOL RAW: \(text.prefix(400))")
        } catch {
            print("FMPROBE TOOL RESULT: ERROR \(error.localizedDescription)")
        }
    }

    /// DEBUG-only on-device probe for the document pipeline and the tool gates that
    /// were reported broken. Runs the reported flows end to end on real hardware:
    ///
    ///   DEVICECTL_CHILD_DOC_PROBE=1 xcrun devicectl device process launch --console ...
    @MainActor
    static func runDocumentProbe() async {
        print("DOCPROBE start")

        // 1. Greeting gate — a social prompt must not advertise tools, a real
        //    request must keep them.
        print("DOCPROBE socialOnly(hi)=\(UpfrontToolDetector.isSocialOnly(prompt: "hi"))")
        print("DOCPROBE socialOnly(Hi there!)=\(UpfrontToolDetector.isSocialOnly(prompt: "Hi there!"))")
        print("DOCPROBE socialOnly(hey can you help me search the web)=\(UpfrontToolDetector.isSocialOnly(prompt: "hey can you help me search the web"))")
        print("DOCPROBE socialOnly(what time is it)=\(UpfrontToolDetector.isSocialOnly(prompt: "what time is it"))")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docprobe-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("contract.txt")
            try """
            Termination. Either party may end this agreement with 30 days written notice. \
            The notice period for termination must be given in writing to the other party.
            """.write(to: file, atomically: true, encoding: .utf8)

            let library = DocumentLibraryStore(directory: dir)
            let imported = await library.importDocument(from: file)
            print("DOCPROBE imported=\(imported?.fileName ?? "nil") chunks=\(imported?.chunkCount ?? -1) kind=\(String(describing: imported?.embeddingKind))")

            let index = library.searchIndex()
            print("DOCPROBE indexEmpty=\(index.isEmpty) indexChunks=\(index.chunkCount)")

            guard let item = MockCatalogData.items.first(where: { $0.runtimeType == .foundationModels }) else {
                print("DOCPROBE ERROR no catalog model")
                return
            }
            let model = InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1,
                localPath: AppleFoundationModelService.localPathMarker
            )
            let settings = AppSettings.default
            let context = ToolContext(
                settings: settings,
                conversation: [],
                chatSessions: [],
                attachedDocuments: [],
                installedModel: model,
                documentSearchIndex: index
            )

            // 2. The Apple Intelligence argument shape: a BARE STRING. This is the
            //    exact payload that used to fail with "query argument is required",
            //    making the model tell the user to upload the document.
            let bare = await SearchDocumentsTool().run(
                argsJSON: "what is the notice period for termination",
                context: context
            )
            print("DOCPROBE bareString ok=\(!bare.output.hasPrefix("Error")) out=\(bare.output.prefix(140))")

            // 3. The full pipeline for that payload: model text -> StreamProcessor ->
            //    ToolRegistry.dispatch -> real passages.
            let aiPayload = #"<tool_call>{"name": "search_documents", "arguments": "what is the notice period for termination"}</tool_call>"#
            await runPipeline(payload: aiPayload, label: "appleIntelligence", context: context)

            // 4. The flat shape Gemma/LFM emit, which used to lose its arguments.
            let flatPayload = #"<tool_call>{"name": "search_documents", "query": "notice period termination"}</tool_call>"#
            await runPipeline(payload: flatPayload, label: "flatQuery", context: context)

            // 5. A natural question must reach the library for a model with no tool loop.
            let upfront = await UpfrontToolDetector.detectAndRun(
                prompt: "What does the contract say about termination?",
                context: context
            )
            print("DOCPROBE upfrontTools=\(upfront.map(\.toolName)) reachedLibrary=\(upfront.contains { $0.toolName == "search_documents" })")

            print("DOCPROBE done")
        } catch {
            print("DOCPROBE ERROR \(error.localizedDescription)")
        }
    }

    private static func runPipeline(payload: String, label: String, context: ToolContext) async {
        let raw = AsyncStream<String> { continuation in
            continuation.yield(payload)
            continuation.finish()
        }
        let processor = StreamProcessor(
            rawStream: raw,
            v2Enabled: AppSettings.default.streamProcessorV2Enabled,
            hangTimeout: AppSettings.default.inferenceV2Timeout
        )

        var name: String?
        var args: String?
        for await event in await processor.process() {
            if case .toolCall(let parsedName, let parsedArgs) = event {
                name = parsedName
                args = parsedArgs
            }
        }

        guard let name, let args else {
            print("DOCPROBE \(label) NO_TOOL_CALL parsed")
            return
        }

        let result = await ToolRegistry.dispatch(name: name, argsJSON: args, context: context)
        let output = result?.output ?? "nil"
        print("DOCPROBE \(label) name=\(name) args=\(args.prefix(70)) ok=\(!(output.hasPrefix("Error"))) out=\(output.prefix(140))")
    }

    /// Renders a high-contrast word so the result is unambiguous.
    private static func probeImage(word: String) -> UIImage? {
        let size = CGSize(width: 900, height: 300)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 110, weight: .black),
                .foregroundColor: UIColor.black
            ]
            let textSize = word.size(withAttributes: attributes)
            word.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
#endif
