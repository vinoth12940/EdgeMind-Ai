import XCTest
@testable import EdgeMindAi

final class CustomSearchGatewayTests: XCTestCase {

    func testNormalizesRootGatewayURLToSearchEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "https://search.example.com"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "https://search.example.com/api/search")
    }

    func testNormalizesHealthURLToSearchEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "https://search.example.com/health"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "https://search.example.com/api/search")
    }

    func testPreservesExplicitCustomEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/custom/search"))

        let normalized = CustomSearchGateway.normalizedEndpoint(from: input)

        XCTAssertEqual(normalized.absoluteString, "https://example.com/custom/search")
    }

    func testDefaultSettingsDoNotAssumeBundledSearchGateway() throws {
        XCTAssertNil(AppSettings.default.searchGatewayURL)
    }

    func testFactoryDoesNotCreateGatewayWhenSearchIsDisabledByDefault() {
        let gateway = SearchGatewayFactory.make(settings: .default)

        XCTAssertNil(gateway)
    }

    func testFactoryCreatesCustomGatewayWhenExplicitlyConfigured() throws {
        var settings = AppSettings.default
        settings.webSearchProvider = .custom
        settings.searchGatewayURL = try XCTUnwrap(URL(string: "https://search.example.com/api/search"))

        let gateway = SearchGatewayFactory.make(settings: settings)

        XCTAssertNotNil(gateway)
        XCTAssertTrue(gateway is CustomSearchGateway)
    }

    func testFactoryDoesNotAutoEnableFallbackGatewayUntilExplicitlySelected() {
        XCTAssertFalse(SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: .default))
    }

    func testConfiguredProviderDoesNotAutoEnableLiveSearchByItself() {
        var settings = AppSettings.default
        settings.webSearchProvider = .serper
        settings.webSearchAPIKey = "test-key"
        settings.useSearchByDefault = false

        XCTAssertNotNil(SearchGatewayFactory.make(settings: settings))
        XCTAssertFalse(SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: settings))
    }

    func testExplicitSearchDefaultAutoEnablesOnlyWhenGatewayIsUsable() {
        var settings = AppSettings.default
        settings.webSearchProvider = .serper
        settings.webSearchAPIKey = "test-key"
        settings.useSearchByDefault = true

        XCTAssertTrue(SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: settings))

        settings.webSearchAPIKey = ""
        XCTAssertFalse(SearchGatewayFactory.shouldAutoEnableLiveSearch(settings: settings))
    }
}
