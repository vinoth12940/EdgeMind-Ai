// LocalAIEdgeAppTests/AppStateStoreMigrationTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class AppStateStoreMigrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearPersistedStore()
    }

    override func tearDown() {
        clearPersistedStore()
        super.tearDown()
    }

    @MainActor
    func test_initRemovesDeprecatedOpenELMAndKeepsSupportedModels() {
        let openELM = deprecatedItem(
            name: "OpenELM 1.1B Instruct (MLX)",
            family: .openELM,
            modelID: "mlx-community/OpenELM-1_1B-Instruct-4bit"
        )
        let lfm = deprecatedItem(
            name: "LFM2.5 1.2B Instruct (MLX)",
            family: .lfm,
            modelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit"
        )
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )
        var settings = AppSettings.default
        settings.defaultModelID = openELM.id

        let store = AppStateStore(
            catalog: [lfm, qwen],
            installedModels: [
                InstalledModel(catalogItem: openELM, installState: .installed, progress: 1, isDefault: true),
                InstalledModel(catalogItem: lfm, installState: .installed, progress: 1),
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1)
            ],
            chatSessions: [],
            settings: settings
        )

        XCTAssertEqual(store.installedModels.map(\.catalogItem.mlxModelID), [lfm.mlxModelID, qwen.mlxModelID])
        XCTAssertNil(store.settings.defaultModelID)
    }

    @MainActor
    func test_initNormalizesPersistedMLXPathForCurrentCatalogItem() {
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )

        let store = AppStateStore(
            catalog: [qwen],
            installedModels: [
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1, localPath: nil)
            ],
            chatSessions: [],
            settings: .default
        )

        XCTAssertEqual(store.installedModels.first?.localPath, qwen.mlxModelID)
    }

    @MainActor
    func test_setDefaultModelAcceptsInstalledMLXModelOnDeviceBuilds() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX chat models are intentionally hidden in simulator builds.")
        #else
        let qwen = deprecatedItem(
            name: "Qwen 3 0.6B (MLX)",
            family: .qwen,
            modelID: "mlx-community/Qwen3-0.6B-4bit"
        )
        let store = AppStateStore(
            catalog: [qwen],
            installedModels: [
                InstalledModel(catalogItem: qwen, installState: .installed, progress: 1, localPath: qwen.mlxModelID)
            ],
            chatSessions: [],
            settings: .default
        )

        store.setDefaultModel(id: qwen.id)

        XCTAssertEqual(store.defaultModel?.catalogItem.id, qwen.id)
        XCTAssertEqual(store.settings.defaultModelID, qwen.id)
        #endif
    }

    private func deprecatedItem(
        name: String,
        family: ModelCatalogItem.ModelFamily,
        modelID: String
    ) -> ModelCatalogItem {
        ModelCatalogItem(
            displayName: name,
            family: family,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1B",
            quantization: "MLX 4-bit",
            diskSize: "~1 GB",
            contextWindow: "2K",
            runtimeType: .mlx,
            mlxModelID: modelID,
            minimumTier: .standard
        )
    }

    private func clearPersistedStore() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "persistedInstalledModels")
        defaults.removeObject(forKey: "persistedAppSettings")
        defaults.removeObject(forKey: "persistedChatSessions")
        defaults.removeObject(forKey: "persistedSelectedSessionID")
    }
}
