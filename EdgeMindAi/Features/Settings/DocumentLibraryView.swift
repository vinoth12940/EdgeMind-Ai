import SwiftUI
import UniformTypeIdentifiers

/// Settings → AI Configuration → Documents. Imports files into the on-device
/// library, shows indexing state, and gates document search.
struct DocumentLibraryView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(DocumentLibraryStore.self) private var library

    @State private var showImporter = false
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack {
            AppBackdropView()

            List {
                Section {
                    Toggle("Search my documents in chat", isOn: Binding(
                        get: { store.settings.documentSearchEnabled },
                        set: { store.settings.documentSearchEnabled = $0; store.persistSettings() }
                    ))
                    .font(.appBody(14))

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import a document…", systemImage: "square.and.arrow.down")
                            .font(.appBody(14))
                    }
                } footer: {
                    Text("Documents, chunks, and embeddings stay in this app's private storage on this device. Nothing is uploaded.")
                }

                Section {
                    if library.documents.isEmpty {
                        Text("No documents imported yet.")
                            .font(.appBody(13))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(library.documents) { document in
                            documentRow(document)
                        }
                        .onDelete(perform: delete)
                    }
                } header: {
                    Text("Library (\(library.documents.count))")
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("Remove all documents")
                            .font(.appBody(14))
                    }
                    .disabled(library.documents.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: DocumentExtractionService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await library.importDocument(from: url) }
        }
        .alert("Remove all documents?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove all", role: .destructive) {
                library.removeAll()
            }
        } message: {
            Text("This deletes every imported document and its index from this device.")
        }
    }

    private func documentRow(_ document: LibraryDocument) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                library.setEnabled(!document.isEnabled, for: document.id)
            } label: {
                Image(systemName: document.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(document.isEnabled ? AppTheme.success : AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(document.isEnabled ? "Disable document" : "Enable document")
            .disabled(!document.isReady)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.fileName)
                    .font(.appBody(14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                statusLine(for: document)
            }

            Spacer(minLength: 0)

            if let progress = library.indexingProgress[document.id] {
                ProgressView(value: progress)
                    .frame(width: 44)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusLine(for document: LibraryDocument) -> some View {
        switch document.indexState {
        case .indexing:
            Text("Indexing…")
                .font(.appBody(11))
                .foregroundStyle(AppTheme.textSecondary)
        case .ready:
            Text("\(document.chunkCount) chunks · \(embeddingLabel(document.embeddingKind))")
                .font(.appBody(11))
                .foregroundStyle(AppTheme.textSecondary)
        case .failed(let message):
            Text(message)
                .font(.appBody(11))
                .foregroundStyle(AppTheme.warning)
                .lineLimit(2)
        }
    }

    private func embeddingLabel(_ kind: DocumentEmbeddingKind) -> String {
        switch kind {
        case .contextual: return "contextual embeddings"
        case .sentence: return "sentence embeddings"
        case .none: return "keyword search only"
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets where library.documents.indices.contains(offset) {
            library.remove(id: library.documents[offset].id)
        }
    }
}
