// LocalAIEdgeAppTests/ModelCatalogItemTests.swift
import XCTest
@testable import LocalAIEdgeApp

final class ModelCatalogItemTests: XCTestCase {

    func test_estimatedResidentGB_textOnly() {
        let item = ModelCatalogItem(
            displayName: "Test 1.7B",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1.7B",
            quantization: "MLX 4-bit",
            diskSize: "~1.7 GB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/x",
            supportsVision: false,
            minimumTier: .standard
        )
        // 1.7 * 1.15 + kvCache(4096) + 0 + 0.3 ≈ 1.955 + ~0.2 + 0.3 ≈ 2.45 GB for standard
        let est = item.estimatedResidentGB(contextTokens: 4096)
        XCTAssertGreaterThan(est, 2.0)
        XCTAssertLessThan(est, 3.0)
    }

    func test_estimatedResidentGB_visionAddsTower() {
        let base = ModelCatalogItem(
            displayName: "Test VL",
            family: .lfm,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "1.6B",
            quantization: "MLX 4-bit",
            diskSize: "~1.5 GB",
            contextWindow: "32K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/y",
            supportsVision: true,
            minimumTier: .standard
        )
        let nonVisionEstimate = 1.5 * 1.15 + 0.3 // ~2.025
        XCTAssertGreaterThan(base.estimatedResidentGB(contextTokens: 2048), nonVisionEstimate + 0.5)
    }

    func test_decodeMissingRecommendedForIPhone_defaultsToFalse() throws {
        let json = """
        {
            "id": "EAD31E2E-0000-5000-A000-000000000000",
            "displayName": "legacy entry",
            "family": "Qwen",
            "provider": "Hugging Face",
            "variant": "MLX",
            "summary": "",
            "parameterSize": "1B",
            "quantization": "MLX 4-bit",
            "diskSize": "1 GB",
            "contextWindow": "40K",
            "runtimeType": "MLX",
            "primaryUse": "chat",
            "sourceSupportsVision": false,
            "supportsVision": false,
            "supportsReasoning": false,
            "supportsToolCalling": false,
            "isThinkingModel": false,
            "minimumTier": "standard"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ModelCatalogItem.self, from: json)
        XCTAssertFalse(decoded.recommendedForIPhone)
        XCTAssertEqual(decoded.minimumTier, .standard)
    }

    func test_parsedDiskSizeGB_handlesMegabytes() {
        let item = ModelCatalogItem(
            displayName: "Tiny",
            family: .qwen,
            variant: "4-bit MLX",
            summary: "",
            parameterSize: "0.6B",
            quantization: "MLX 4-bit",
            diskSize: "~600 MB",
            contextWindow: "40K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/tiny",
            minimumTier: .compact
        )

        XCTAssertEqual(item.parsedDiskSizeGBForEstimator, 600.0 / 1024.0, accuracy: 0.01)
    }

    func test_catalogExcludesOpenELMChatModels() {
        let openELMItems = MockCatalogData.items.filter { $0.family == .openELM }
        XCTAssertTrue(openELMItems.isEmpty)
    }

    func test_proTierRecommendedCatalogFitsProMemoryBudget() {
        let proTier = DeviceTier.pro
        let riskyItems = MockCatalogData.items.filter { item in
            item.recommendedForIPhone
                && item.minimumTier <= proTier
                && item.estimatedResidentGB(contextTokens: proTier.safeContextTokens) > proTier.jetsamSoftLimitGB
        }

        XCTAssertTrue(
            riskyItems.isEmpty,
            "Pro-tier recommended catalog includes memory-risky models: \(riskyItems.map(\.displayName).joined(separator: ", "))"
        )
    }

    func test_catalogKeepsLFMModelsIncluding350M() {
        let lfmModelIDs = MockCatalogData.items
            .filter { $0.family == .lfm }
            .compactMap(\.mlxModelID)

        XCTAssertEqual(
            lfmModelIDs,
            [
                "mlx-community/LFM2.5-VL-1.6B-4bit",
                "mlx-community/LFM2.5-350M-6bit",
                "mlx-community/LFM2.5-1.2B-Thinking-6bit",
                "mlx-community/LFM2.5-1.2B-Instruct-4bit"
            ]
        )
    }

    func test_catalogIncludesGraniteMLXModels() {
        let graniteItems = MockCatalogData.items.filter { $0.family == .granite }

        XCTAssertEqual(
            graniteItems.compactMap(\.mlxModelID),
            [
                "mlx-community/granite-3.3-2b-instruct-4bit"
            ]
        )
        XCTAssertTrue(graniteItems.allSatisfy { $0.runtimeType == .mlx })
        XCTAssertTrue(graniteItems.allSatisfy { !$0.supportsVision })
    }

    func test_recommendedCatalogRequiresGreenAuditVerdict() {
        let unsafeRecommended = MockCatalogData.items.filter { item in
            item.recommendedForIPhone
                && (item.runtimeStatus != .recommended || item.auditVerdict != .green)
        }

        XCTAssertTrue(
            unsafeRecommended.isEmpty,
            "Recommended models must be green-audited: \(unsafeRecommended.map(\.displayName).joined(separator: ", "))"
        )
    }

    func test_shippedCatalogContainsOnlyWorkingModels() {
        let nonWorkingItems = MockCatalogData.items.filter { item in
            item.auditVerdict != .green || item.runtimeStatus == .unsupported
        }

        XCTAssertTrue(
            nonWorkingItems.isEmpty,
            "Shipped catalog must not include broken or pending models: \(nonWorkingItems.map(\.displayName).joined(separator: ", "))"
        )
    }

    func test_ggufVisionFamiliesAreTextOnlyInAppRuntime() {
        let ggufVisionFamilyItems = MockCatalogData.items.filter { item in
            item.runtimeType == .gguf && item.sourceSupportsVision
        }

        XCTAssertTrue(ggufVisionFamilyItems.allSatisfy { !$0.runtimeInputCategories.contains(.image) })
    }
}
