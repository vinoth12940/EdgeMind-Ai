import SwiftUI
import UniformTypeIdentifiers

/// Sheet shown inside the Share Extension. It only reads the shared item, writes
/// it to the App Group inbox, and asks the app to open — no inference runs here.
struct ShareSheetView: View {
    let inputItems: [NSExtensionItem]
    let onCancel: () -> Void
    let onShare: (SharePayload) -> Void

    @State private var action: ShareAction = .summarize
    @State private var question = ""
    @State private var status = "Reading the shared item…"
    @State private var isReady = false
    @State private var isSaving = false

    private static let maxFileBytes = 50 * 1024 * 1024

    private var canShare: Bool {
        isReady && !isSaving && (action != .ask || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(ShareAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if action == .ask {
                    Section("Question") {
                        TextField("Ask about this…", text: $question, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }

                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edge Mind AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { Task { await save() } }
                        .disabled(!canShare)
                }
            }
            .task { await loadSharedItem() }
        }
    }

    // MARK: - Extraction

    @State private var sharedText: String?
    @State private var sharedFileName: String?
    @State private var sharedFileData: Data?

    private func loadSharedItem() async {
        let attachments = inputItems.flatMap { $0.attachments ?? [] }
        guard !attachments.isEmpty else {
            status = "Nothing was shared."
            return
        }

        for provider in attachments {
            if let text = await loadText(from: provider), !text.isEmpty {
                sharedText = text
            }
            if let url = await loadURL(from: provider), sharedText == nil {
                sharedText = url.absoluteString
            }
            if let file = await loadFile(from: provider) {
                sharedFileName = file.name
                sharedFileData = file.data
            }
            if sharedText != nil || sharedFileName != nil { break }
        }

        if sharedFileName != nil {
            status = "Ready to import the file into your on-device library."
        } else if sharedText != nil {
            status = "Ready to share the text with Edge Mind AI."
        } else {
            status = "This item type isn't supported yet."
        }
        isReady = sharedText != nil || sharedFileName != nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadFile(from provider: NSItemProvider) async -> (name: String, data: Data)? {
        let identifier = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .pdf)
                || type.conforms(to: .plainText)
                || type.conforms(to: .commaSeparatedText)
                || type.conforms(to: .image)
        }
        guard let identifier else { return nil }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url), data.count <= Self.maxFileBytes else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (url.lastPathComponent, data))
            }
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let payload = SharePayload(
            action: action,
            question: action == .ask ? question.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            text: sharedText,
            fileName: sharedFileName
        )

        do {
            try ShareInbox().enqueue(payload, fileContents: sharedFileData)
            onShare(payload)
        } catch {
            status = error.localizedDescription
        }
    }
}
