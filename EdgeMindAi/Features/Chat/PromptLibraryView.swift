// LocalAIEdgeApp/Features/Chat/PromptLibraryView.swift
import SwiftUI

/// Sheet that lets the user pick a built-in prompt template. On pick, the template
/// body is written into the bound `prompt` (appended to existing text with a newline
/// separator, or replaced if empty) and the sheet dismisses.
struct PromptLibraryView: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [PromptTemplate] = []
    @State private var preview: PromptTemplate?

    var grouped: [(category: String, templates: [PromptTemplate])] {
        let store = PromptTemplateStore()
        return store.grouped
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.category) { section in
                    Section(section.category) {
                        ForEach(section.templates) { template in
                            Button {
                                insert(template)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: template.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 30)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text(template.body.isEmpty ? "Empty template" : previewLine(template.body))
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    preview = template
                                } label: {
                                    Label("Preview", systemImage: "eye")
                                }
                                .tint(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.panel.opacity(0.4))
            .navigationTitle("Prompt Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .sheet(item: $preview) { template in
                PromptPreviewSheet(template: template) {
                    insert(template)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func insert(_ template: PromptTemplate) {
        let body = template.body
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the composer is empty, replace it; otherwise append so the user can keep
        // what they typed and have the template act as a prefix/instruction.
        if trimmedPrompt.isEmpty {
            prompt = body
        } else {
            prompt = body + trimmedPrompt
        }
        isFocused.wrappedValue = true
        dismiss()
    }

    private func previewLine(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Read-only preview of a single template before inserting.
private struct PromptPreviewSheet: View {
    let template: PromptTemplate
    let onUse: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: template.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text(template.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                    }

                    Text(template.category)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.12))
                        .clipShape(Capsule())

                    Text(template.body.isEmpty ? "(empty)" : template.body)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppTheme.panelRaised.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        )
                }
                .padding(20)
            }
            .background(AppTheme.panel.opacity(0.4))
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") { onUse() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}
