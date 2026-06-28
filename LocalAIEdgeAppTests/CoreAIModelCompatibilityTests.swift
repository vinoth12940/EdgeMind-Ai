import XCTest
@testable import LocalAIEdgeApp

final class CoreAIModelCompatibilityTests: XCTestCase {
    func test_coreAICompatibilityHasStatusForEveryCatalogItem() {
        let statuses = CoreAIModelCompatibility.allStatuses(for: MockCatalogData.items)

        XCTAssertEqual(statuses.count, MockCatalogData.items.count)
    }

    func test_coreAIiOSPresetListMatchesApplePublishedRegistrySubset() {
        let presets = CoreAIModelCompatibility.iOSLLMPresets

        XCTAssertEqual(presets.map(\.shortName), [
            "qwen3-0.6b",
            "qwen2.5-1.5b-instruct",
            "qwen3-4b"
        ])
        XCTAssertTrue(presets.allSatisfy { $0.contextTokens == 4_096 })
    }

    func test_qwen306BHasDirectCoreAIPresetButCurrentBuildKeepsExistingRuntime() throws {
        let item = try XCTUnwrap(MockCatalogData.items.first { $0.displayName == "Qwen 3 0.6B (MLX)" })

        let status = CoreAIModelCompatibility.status(for: item)

        if case .directLLMPreset(let preset) = status {
            XCTAssertEqual(preset.huggingFaceID, "Qwen/Qwen3-0.6B")
        } else {
            XCTFail("Expected Qwen 3 0.6B to map to Apple's iOS Core AI preset.")
        }
        XCTAssertFalse(status.canUseCoreAIRuntimeInThisBuild)
        XCTAssertEqual(item.runtimeType, .mlx)
    }

    func test_qwen34B2507IsRelatedButNotDirectCoreAIPreset() throws {
        let item = try XCTUnwrap(MockCatalogData.items.first { $0.displayName == "Qwen 3 4B 2507 Instruct (GGUF)" })

        let status = CoreAIModelCompatibility.status(for: item)

        if case .relatedLLMPreset(let preset, let note) = status {
            XCTAssertEqual(preset.huggingFaceID, "Qwen/Qwen3-4B")
            XCTAssertTrue(note.contains("2507"))
        } else {
            XCTFail("Expected Qwen 3 4B 2507 to be related, not a direct preset match.")
        }
        XCTAssertEqual(item.runtimeType, .gguf)
    }

    func test_lfmModelsAreNotMarkedCoreAICapable() {
        let lfmStatuses = MockCatalogData.items
            .filter { $0.family == .lfm }
            .map(CoreAIModelCompatibility.status)

        XCTAssertFalse(lfmStatuses.isEmpty)
        XCTAssertTrue(lfmStatuses.allSatisfy {
            if case .notRegistered = $0 { return true }
            return false
        })
    }

    func test_coreAIPackageRequirementIsNotCompatibleWithCurrentDeploymentTarget() {
        XCTAssertEqual(CoreAIModelCompatibility.minimumRuntimePlatform, "iOS 27.0")
        XCTAssertEqual(CoreAIModelCompatibility.minimumXcodeVersion, "Xcode 27.0")
    }
}
