import Foundation
import OSLog

private let shareProcessorLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ShareInboxProcessor")

/// What a drained share item should do to the chat.
struct ShareImportOutcome: Equatable {
    var prompt: String
    var attachments: [ChatAttachment]
    var importedDocumentNames: [String]

    var shouldAutoSend: Bool { !prompt.isEmpty }
}

/// Turns a `SharePayload` into a chat turn and (for files) a library import.
/// All work is local; shared URLs are only ever passed as text (never fetched).
@MainActor
enum ShareInboxProcessor {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]

    /// Processes one payload and removes it from the inbox. Returns nil when the
    /// payload has nothing usable.
    static func process(
        _ payload: SharePayload,
        inbox: ShareInbox = ShareInbox(),
        library: DocumentLibraryStore
    ) async -> ShareImportOutcome? {
        // Claim the item BEFORE the first `await`. The inbox is drained from `onAppear`
        // and `didBecomeActive` while the `share/<id>` deep link can also be handling the
        // same payload, and `library.importDocument` suspends on the DocumentIndexer
        // actor. Without this claim both callers passed the "is it still pending?" check
        // and the shared file was imported into the library twice.
        guard inbox.claim(id: payload.id) else {
            shareProcessorLogger.log("Share item \(payload.id.uuidString, privacy: .public) was already claimed")
            return nil
        }

        var outcome = ShareImportOutcome(
            prompt: payload.resolvedPrompt,
            attachments: [],
            importedDocumentNames: []
        )
        // A summarize/explain prompt is only meaningful with real content, so
        // track whether anything usable was actually carried in.
        var hasContent = false

        if let fileURL = inbox.fileURL(for: payload) {
            let fileExtension = fileURL.pathExtension.lowercased()
            if imageExtensions.contains(fileExtension) {
                if let data = try? Data(contentsOf: fileURL) {
                    outcome.attachments.append(.image(data, fileName: payload.fileName ?? fileURL.lastPathComponent))
                    hasContent = true
                }
            } else {
                if let document = await library.importDocument(from: fileURL) {
                    outcome.importedDocumentNames.append(document.fileName)
                    hasContent = true
                }
                // Also inline the extracted text so the first turn has context
                // without a tool round-trip.
                if let attachment = try? await DocumentExtractionService.attachment(from: fileURL),
                   let text = attachment.extractedText,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    outcome.attachments.append(ChatAttachment(
                        kind: attachment.kind,
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        extractedText: text
                    ))
                    hasContent = true
                }
            }
        } else if let text = payload.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasContent = true
            outcome.attachments.append(ChatAttachment(
                kind: .text,
                fileName: "Shared text",
                mimeType: "text/plain",
                extractedText: text
            ))
            if case .ask = payload.action, outcome.prompt.isEmpty {
                outcome.prompt = text
            }
            if case .summarize = payload.action {
                outcome.prompt = payload.resolvedPrompt
            }
        }

        inbox.remove(id: payload.id)

        guard hasContent else {
            shareProcessorLogger.log("Discarded empty share item \(payload.id.uuidString, privacy: .public)")
            return nil
        }
        return outcome
    }

    /// Processes every pending item (oldest first) and returns the outcomes.
    static func drainPending(
        inbox: ShareInbox = ShareInbox(),
        library: DocumentLibraryStore
    ) async -> [ShareImportOutcome] {
        var outcomes: [ShareImportOutcome] = []
        for payload in inbox.pending() {
            if let outcome = await process(payload, inbox: inbox, library: library) {
                outcomes.append(outcome)
            }
        }
        return outcomes
    }
}
