import XCTest
@testable import LocalAIEdgeApp

final class CustomSearchGatewayTests: XCTestCase {

    func testNormalizesRootGatewayURLToSearchEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "http://localhost:8787"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "http://localhost:8787/api/search")
    }

    func testNormalizesHealthURLToSearchEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "http://localhost:8787/health"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "http://localhost:8787/api/search")
    }

    func testPreservesExplicitCustomEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/custom/search"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "https://example.com/custom/search")
    }

    func testDefaultSettingsUseWorkingSearchGatewayPath() throws {
        XCTAssertEqual(AppSettings.default.searchGatewayURL?.absoluteString, "http://localhost:8787/api/search")
    }

    func testFactoryFallsBackToCustomGatewayWhenURLExists() {
        let gateway = SearchGatewayFactory.make(settings: .default)

        XCTAssertNotNil(gateway)
        XCTAssertTrue(gateway is CustomSearchGateway)
    }

    func testFactoryDoesNotAutoEnableFallbackGatewayUntilExplicitlySelected() {
        XCTAssertFalse(SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: .default))
    }
}
