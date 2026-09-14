import SwiftUI

/// Format picker + "Include thinking" toggle + `ShareLink` for the current chat.
/// The export is regenerated whenever an option changes.
struct ChatExportSheet: View {
    let session: ChatSession

    @Environment(\.dismiss) private var dismiss
    @State private var format: ChatExporter.Format = .markdown
    @State private var includeThinking = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    private var optionsKey: String {
        "\(format.rawValue)-\(includeThinking)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Format", selection: $format) {
                    ForEach(ChatExporter.Format.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Include thinking", isOn: $includeThinking)
                    .font(.appBody(14))

                Group {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share \(format.displayName) file", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(AppTheme.accent.opacity(0.18)))
                                .foregroundStyle(AppTheme.accent)
                        }
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.appBody(13))
                            .foregroundStyle(AppTheme.warning)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing export…")
                                .font(.appBody(13))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                Text("Exports are written to a temporary folder on this device and removed the next time you export.")
                    .font(.appBody(11))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Share chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: optionsKey) {
                await prepare()
            }
        }
    }

    private func prepare() async {
        exportURL = nil
        errorMessage = nil
        do {
            exportURL = try await ChatExporter.export(
                session: session,
                format: format,
                includeThinking: includeThinking
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
