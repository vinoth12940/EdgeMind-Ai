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
}
