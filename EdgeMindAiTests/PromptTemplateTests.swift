import XCTest
@testable import EdgeMindAi

/// Verifies the bundled PromptTemplates.json loads, decodes, and round-trips.
/// Mirrors the belt-and-braces pattern in `RuntimeProfileTests`.
final class PromptTemplateTests: XCTestCase {

    // MARK: - Bundled JSON resolution

    func test_bundledJSONResolvesFromAppBundle() throws {
        let url = try XCTUnwrap(
            Bundle(for: PromptTemplateTests.self).url(forResource: "PromptTemplates", withExtension: "json")
                ?? Bundle.main.url(forResource: "PromptTemplates", withExtension: "json")
        )
        let templates = try JSONDecoder().decode([PromptTemplate].self, from: Data(contentsOf: url))
        // Sanity: the shipped library has a meaningful number of templates.
        XCTAssertGreaterThanOrEqual(templates.count, 10, "Expected ≥10 bundled templates, got \(templates.count)")
    }

    func test_promptTemplateStoreLoadsBundledTemplates() throws {
        let store = PromptTemplateStore()
        XCTAssertFalse(store.templates.isEmpty, "Store should load bundled templates")
        // Each template must have a stable slug + non-empty body.
        for t in store.templates {
            XCTAssertFalse(t.slug.isEmpty, "Template \(t.title) has empty slug")
            XCTAssertFalse(t.body.isEmpty, "Template \(t.title) has empty body")
            XCTAssertFalse(t.icon.isEmpty, "Template \(t.title) has empty icon")
        }
    }

    func test_storeGroupsTemplatesByCategory() throws {
        let store = PromptTemplateStore()
        let grouped = store.grouped
        XCTAssertFalse(grouped.isEmpty)
        // Every group must be non-empty and share its category label.
        for (category, items) in grouped {
            XCTAssertFalse(items.isEmpty, "Category \(category) is empty")
            XCTAssertTrue(items.allSatisfy { $0.category == category })
        }
    }

    // MARK: - Codable round-trip

    func test_promptTemplateCodableRoundTrip() throws {
        let original = PromptTemplate(
            slug: "test-slug",
            title: "Test Template",
            body: "Do the thing:\n\n",
            category: "Test",
            icon: "hammer"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PromptTemplate.self, from: encoded)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.slug, "test-slug")
        XCTAssertEqual(decoded.title, "Test Template")
        XCTAssertEqual(decoded.body, "Do the thing:\n\n")
        XCTAssertEqual(decoded.category, "Test")
        XCTAssertEqual(decoded.icon, "hammer")
    }

    // MARK: - Deterministic IDs

    func test_deterministicIDStableAcrossLaunches() {
        // Same slug + category → same UUID, every time.
        let a = PromptTemplate.deterministicID(slug: "summarize", category: "Writing")
        let b = PromptTemplate.deterministicID(slug: "summarize", category: "Writing")
        XCTAssertEqual(a, b)
    }

    func test_deterministicIDDiffersByCategory() {
        let writing = PromptTemplate.deterministicID(slug: "brainstorm", category: "Productivity")
        let learning = PromptTemplate.deterministicID(slug: "brainstorm", category: "Learning")
        XCTAssertNotEqual(writing, learning)
    }

    func test_deterministicIDDiffersFromCatalogNamespace() {
        // Tool/template/catalog namespaces are distinct so IDs never collide.
        let template = PromptTemplate.deterministicID(slug: "summarize", category: "Writing")
        let catalog = DeterministicID.uuidV5(namespace: DeterministicID.modelCatalogNamespace, name: "summarize::Writing")
        XCTAssertNotEqual(template, catalog)
    }

    // MARK: - Decode with defaults

    func test_decodeFillsMissingOptionalFields() throws {
        // JSON omits category/icon/requiredCapability — decoder must default them.
        let json = """
        {"slug": "bare", "title": "Bare", "body": "Hi"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PromptTemplate.self, from: json)
        XCTAssertEqual(decoded.slug, "bare")
        XCTAssertEqual(decoded.category, "General", "Missing category should default to General")
        XCTAssertEqual(decoded.icon, "text.bubble", "Missing icon should default to text.bubble")
        XCTAssertNil(decoded.requiredCapability)
    }
}
