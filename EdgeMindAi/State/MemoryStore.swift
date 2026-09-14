import Foundation
import Observation

/// On-device personal memories, persisted under their own UserDefaults key.
/// Deliberately separate from `AppStateStore`: memories are not chat state and
/// never leave the device.
@MainActor
@Observable
final class MemoryStore {
    /// Hard cap on stored memories (spec §1).
    static let maxItems = 50
    private static let storageKey = "persistedMemoryItems"

    private(set) var items: [MemoryItem]

    init(items: [MemoryItem]? = nil) {
        if let items {
            self.items = Self.normalized(items)
        } else {
            self.items = Self.normalized(Self.loadPersisted())
        }
    }

    /// Rendered memory section plus how many items it contains.
    struct PromptSection: Equatable {
        let text: String
        let includedCount: Int
    }

    // MARK: - Mutations

    /// Adds a memory, truncating to `MemoryItem.maxTextCharacters` and evicting
    /// the oldest item when the cap is reached. Returns the stored item.
    @discardableResult
    func add(_ text: String) -> MemoryItem? {
        let item = MemoryItem(text: text)
        guard !item.text.isEmpty else { return nil }

        items.append(item)
        if items.count > Self.maxItems {
            items.removeFirst(items.count - Self.maxItems)
        }
        persist()
        return item
    }

    func update(id: UUID, text: String? = nil, isEnabled: Bool? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let text {
            let clamped = MemoryItem.clamped(text)
            guard !clamped.isEmpty else { return }
            items[index].text = clamped
        }
        if let isEnabled {
            items[index].isEnabled = isEnabled
        }
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    // MARK: - Prompt rendering

    /// Builds the `# About the user` section from the enabled memories,
    /// newest first, stopping before the token budget is exceeded.
    func promptSection(budgetTokens: Int) -> PromptSection {
        let enabled = items.filter(\.isEnabled).reversed()
        guard !enabled.isEmpty else { return PromptSection(text: "", includedCount: 0) }

        var lines: [String] = []
        var usedTokens = 0
        for item in enabled {
            let cost = Self.estimatedTokens(item.text)
            if usedTokens + cost > budgetTokens, !lines.isEmpty { break }
            lines.append("- \(item.text)")
            usedTokens += cost
        }

        guard !lines.isEmpty else { return PromptSection(text: "", includedCount: 0) }

        let section = (["# About the user"] + lines).joined(separator: "\n")
        return PromptSection(text: section, includedCount: lines.count)
    }

    /// Budgeted against the running model's safe context window.
    func promptSection(for model: InstalledModel) -> PromptSection {
        promptSection(budgetTokens: InferenceBudget.memoryTokenBudget(for: model))
    }

    /// Cheap, dependency-free token estimate (~4 characters per token).
    static func estimatedTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadPersisted() -> [MemoryItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func normalized(_ items: [MemoryItem]) -> [MemoryItem] {
        var result = items.map { item in
            var copy = item
            copy.text = MemoryItem.clamped(item.text)
            return copy
        }
        result.removeAll { $0.text.isEmpty }
        if result.count > maxItems {
            result.removeFirst(result.count - maxItems)
        }
        return result
    }
}

/// Detects "remember that …", "remember I …", and "don't forget …" in a prompt
/// so the composer can offer to save the rest as a memory. Pure and testable.
enum MemoryPhraseDetector {
    private static let prefixes = [
        "remember that ",
        "remember i ",
        "remember ",
        "don't forget that ",
        "don't forget ",
        "dont forget that ",
        "dont forget "
    ]

    /// Returns the text worth remembering, or nil when no phrase matched or the
    /// remainder is empty.
    static func candidateMemory(from prompt: String) -> String? {
        let lowered = prompt.lowercased()
        for prefix in prefixes {
            // `range(of:)` searches anywhere, so "please remember that …" works too.
            guard let range = lowered.range(of: prefix) else { continue }
            var remainder = String(prompt[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // A bare connector ("remember that", "remember i") is not a memory.
            if ["that", "i"].contains(remainder.lowercased()) {
                remainder = ""
            }
            guard !remainder.isEmpty else { continue }
            return MemoryItem.clamped(remainder)
        }
        return nil
    }
}
