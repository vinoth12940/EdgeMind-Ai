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
        let requested = ProcessInfo.processInfo.arguments.contains("-probe-fm-vision")
            || ProcessInfo.processInfo.environment["FM_VISION_PROBE"] == "1"
        guard requested else { return }

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
