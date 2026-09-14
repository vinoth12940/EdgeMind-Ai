import XCTest
@testable import EdgeMindAi

@MainActor
final class MemoryStoreTests: XCTestCase {
    private static let memoryKey = "persistedMemoryItems"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: Self.memoryKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.memoryKey)
    }

    // MARK: CRUD

    func test_add_storesTrimmedMemory() {
        let store = MemoryStore(items: [])
        let item = store.add("  I live in Austin.  ")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item?.text, "I live in Austin.")
        XCTAssertEqual(item?.isEnabled, true)
    }

    func test_add_rejectsEmptyText() {
        let store = MemoryStore(items: [])
        XCTAssertNil(store.add("   "))
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_update_editsTextAndEnabled() {
        let store = MemoryStore(items: [])
        let item = store.add("Prefers tea")!

        store.update(id: item.id, text: "Prefers coffee", isEnabled: false)

        XCTAssertEqual(store.items.first?.text, "Prefers coffee")
        XCTAssertEqual(store.items.first?.isEnabled, false)
    }

    func test_remove_deletesOnlyThatItem() {
        let store = MemoryStore(items: [])
        let first = store.add("One")!
        store.add("Two")

        store.remove(id: first.id)

        XCTAssertEqual(store.items.map(\.text), ["Two"])
    }

    func test_removeAll_clearsEverything() {
        let store = MemoryStore(items: [])
        store.add("One")
        store.add("Two")

        store.removeAll()

        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: limits

    func test_cap_evictsOldestBeyondFifty() {
        let store = MemoryStore(items: [])
        for index in 0..<(MemoryStore.maxItems + 5) {
            store.add("Memory \(index)")
        }

        XCTAssertEqual(store.items.count, MemoryStore.maxItems)
        XCTAssertEqual(store.items.first?.text, "Memory 5")
        XCTAssertEqual(store.items.last?.text, "Memory 54")
    }

    func test_longText_isClampedToTwoHundredCharacters() {
        let store = MemoryStore(items: [])
        let long = String(repeating: "a", count: 500)

        let item = store.add(long)

        XCTAssertEqual(item?.text.count, MemoryItem.maxTextCharacters)
    }

    // MARK: persistence

    func test_persistence_roundTrip() {
        let store = MemoryStore(items: [])
        store.add("Lives in Austin")
        store.add("Prefers dark mode")

        let reloaded = MemoryStore()

        XCTAssertEqual(reloaded.items.map(\.text), ["Lives in Austin", "Prefers dark mode"])
    }

    func test_normalization_dropsEmptyAndClampsOnLoad() {
        let store = MemoryStore(items: [
            MemoryItem(text: "   "),
            MemoryItem(text: "Kept")
        ])

        XCTAssertEqual(store.items.map(\.text), ["Kept"])
    }

    // MARK: prompt section

    func test_promptSection_isNewestFirstWithHeader() {
        let store = MemoryStore(items: [])
        store.add("Older fact")
        store.add("Newer fact")

        let section = store.promptSection(budgetTokens: 500)

        XCTAssertEqual(section.includedCount, 2)
        let lines = section.text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "# About the user")
        XCTAssertEqual(lines[1], "- Newer fact")
        XCTAssertEqual(lines[2], "- Older fact")
    }

    func test_promptSection_skipsDisabledItems() {
        let store = MemoryStore(items: [])
        let disabled = store.add("Hidden")!
        store.add("Visible")
        store.update(id: disabled.id, isEnabled: false)

        let section = store.promptSection(budgetTokens: 500)

        XCTAssertEqual(section.includedCount, 1)
        XCTAssertFalse(section.text.contains("Hidden"))
        XCTAssertTrue(section.text.contains("Visible"))
    }

    func test_promptSection_stopsBeforeBudget() {
        let store = MemoryStore(items: [])
        // Each line is ~100 characters -> ~25 tokens.
        for index in 0..<10 {
            store.add("Fact \(index) " + String(repeating: "x", count: 90))
        }

        let section = store.promptSection(budgetTokens: 60)

        XCTAssertGreaterThan(section.includedCount, 0)
        XCTAssertLessThan(section.includedCount, 10)
        XCTAssertLessThanOrEqual(
            MemoryStore.estimatedTokens(section.text),
            // The header adds a few tokens beyond the item allowance.
            60 + MemoryStore.estimatedTokens("# About the user")
        )
    }

    func test_promptSection_emptyWhenNoEnabledItems() {
        let store = MemoryStore(items: [])
        XCTAssertEqual(store.promptSection(budgetTokens: 500), MemoryStore.PromptSection(text: "", includedCount: 0))
    }

    // MARK: budget per tier

    func test_memoryTokenBudget_scalesWithTier() {
        let item = MockCatalogData.items.first { $0.displayName == "Qwen 3 0.6B (MLX)" }!
        let model = InstalledModel(catalogItem: item, installState: .installed, progress: 1)

        XCTAssertEqual(InferenceBudget.memoryTokenBudget(for: model, tier: .compact), 150)
        XCTAssertEqual(InferenceBudget.memoryTokenBudget(for: model, tier: .standard), 300)
        XCTAssertEqual(InferenceBudget.memoryTokenBudget(for: model, tier: .pro), 500)
        XCTAssertEqual(InferenceBudget.memoryTokenBudget(for: model, tier: .ultra), 500)
    }
}

final class MemoryPhraseDetectorTests: XCTestCase {
    func test_detectsRememberThatPhrase() {
        XCTAssertEqual(
            MemoryPhraseDetector.candidateMemory(from: "remember that I live in Austin"),
            "I live in Austin"
        )
    }

    func test_detectsRememberIPhrase() {
        XCTAssertEqual(
            MemoryPhraseDetector.candidateMemory(from: "Remember I prefer short answers"),
            "prefer short answers"
        )
    }

    func test_detectsDontForgetPhrase() {
        XCTAssertEqual(
            MemoryPhraseDetector.candidateMemory(from: "don't forget my sister's name is Mia"),
            "my sister's name is Mia"
        )
    }

    func test_returnsNilForOrdinaryPrompt() {
        XCTAssertNil(MemoryPhraseDetector.candidateMemory(from: "What is the weather today?"))
    }

    func test_returnsNilForPhraseWithNoContent() {
        XCTAssertNil(MemoryPhraseDetector.candidateMemory(from: "remember that"))
    }

    func test_clampsLongCandidate() {
        let candidate = MemoryPhraseDetector.candidateMemory(from: "remember that " + String(repeating: "b", count: 400))
        XCTAssertEqual(candidate?.count, MemoryItem.maxTextCharacters)
    }
}
