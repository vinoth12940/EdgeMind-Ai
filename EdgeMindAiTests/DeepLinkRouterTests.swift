import XCTest
@testable import EdgeMindAi

final class DeepLinkRouterTests: XCTestCase {
    private func route(_ string: String) -> DeepLinkRoute? {
        guard let url = URL(string: string) else { return nil }
        return DeepLinkRouter.route(for: url)
    }

    func test_askDefaultsToText() {
        XCTAssertEqual(route("edgemindai://ask"), .ask(mode: .text))
    }

    func test_askReadsModeQuery() {
        XCTAssertEqual(route("edgemindai://ask?mode=voice"), .ask(mode: .voice))
        XCTAssertEqual(route("edgemindai://ask?mode=camera"), .ask(mode: .camera))
    }

    func test_askUnknownModeFallsBackToText() {
        XCTAssertEqual(route("edgemindai://ask?mode=telepathy"), .ask(mode: .text))
    }

    func test_shareCarriesIdentifier() {
        let id = UUID()
        XCTAssertEqual(route("edgemindai://share/\(id.uuidString)"), .share(id))
    }

    func test_settingsRoutes() {
        XCTAssertEqual(route("edgemindai://settings/memory"), .settingsMemory)
        XCTAssertEqual(route("edgemindai://settings/documents"), .settingsDocuments)
    }

    func test_malformedURLsReturnNil() {
        XCTAssertNil(route("https://example.com/ask"))
        XCTAssertNil(route("edgemindai://share"))
        XCTAssertNil(route("edgemindai://share/not-a-uuid"))
        XCTAssertNil(route("edgemindai://settings"))
        XCTAssertNil(route("edgemindai://settings/unknown"))
        XCTAssertNil(route("edgemindai://nonsense"))
    }

    @MainActor
    func test_coordinatorConsumesRouteOnce() {
        let coordinator = DeepLinkCoordinator()
        coordinator.handle(URL(string: "edgemindai://settings/memory")!)

        XCTAssertEqual(coordinator.pendingRoute, .settingsMemory)
        XCTAssertEqual(coordinator.requestedSettingsSection, .memory)
        XCTAssertEqual(coordinator.consumeRoute(), .settingsMemory)
        XCTAssertNil(coordinator.consumeRoute())
        XCTAssertEqual(coordinator.consumeSettingsSection(), .memory)
        XCTAssertNil(coordinator.consumeSettingsSection())
    }
}
