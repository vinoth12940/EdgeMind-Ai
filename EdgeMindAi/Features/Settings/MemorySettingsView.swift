import SwiftUI

/// Settings → AI Configuration → Memory. Lists saved memories with add, edit,
/// enable toggle, swipe-to-delete, and "Clear all" (with confirmation).
struct MemorySettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(MemoryStore.self) private var memoryStore

    @State private var newMemoryText = ""
    @State private var editingItem: MemoryItem?
    @State private var editingText = ""
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack {
            AppBackdropView()

            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("Add a memory (e.g. I live in Austin)", text: $newMemoryText, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.appBody(14))

                        Button {
                            addMemory()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(canAdd ? AppTheme.accent : AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdd)
                        .accessibilityLabel("Save memory")
                    }
                } footer: {
                    Text("Memories stay on this device and are only added to the model prompt when the switch below is on.")
                }

                Section {
                    if memoryStore.items.isEmpty {
                        Text("No memories saved yet.")
                            .font(.appBody(13))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(memoryStore.items.reversed()) { item in
                            memoryRow(item)
                        }
                        .onDelete(perform: delete)
                    }
                } header: {
                    Text("Saved memories (\(memoryStore.items.count)/\(MemoryStore.maxItems))")
                }

                Section {
                    Toggle("Use memories in chat", isOn: Binding(
                        get: { store.settings.memoryEnabled },
                        set: { store.settings.memoryEnabled = $0; store.persistSettings() }
                    ))
                    .font(.appBody(14))

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("Clear all memories")
                            .font(.appBody(14))
                    }
                    .disabled(memoryStore.items.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear all memories?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear all", role: .destructive) {
                memoryStore.removeAll()
            }
        } message: {
            Text("This permanently removes every saved memory from this device.")
        }
        .sheet(item: $editingItem) { item in
            editSheet(for: item)
        }
    }

    private var canAdd: Bool {
        !newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addMemory() {
        guard canAdd else { return }
        memoryStore.add(newMemoryText)
        newMemoryText = ""
    }

    private func delete(at offsets: IndexSet) {
        // The list is rendered newest-first, so map back through the reversed array.
        let reversed = Array(memoryStore.items.reversed())
        for offset in offsets {
            guard reversed.indices.contains(offset) else { continue }
            memoryStore.remove(id: reversed[offset].id)
        }
    }

    private func memoryRow(_ item: MemoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                memoryStore.update(id: item.id, isEnabled: !item.isEnabled)
            } label: {
                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.isEnabled ? AppTheme.success : AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isEnabled ? "Disable memory" : "Enable memory")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.appBody(14))
                    .foregroundStyle(item.isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.appBody(10))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                editingText = item.text
                editingItem = item
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit memory")
        }
        .padding(.vertical, 2)
    }

    private func editSheet(for item: MemoryItem) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Memory", text: $editingText, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.appBody(14))
                    .padding(12)
                    .background(AppTheme.panelRaised.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("\(editingText.count)/\(MemoryItem.maxTextCharacters) characters")
                    .font(.appBody(11))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()
            }
            .padding(16)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Edit memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { editingItem = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        memoryStore.update(id: item.id, text: editingText)
                        editingItem = nil
                    }
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
