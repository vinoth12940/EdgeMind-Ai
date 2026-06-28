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

    func test_modelInstallGuardBlocksModelsAboveCurrentTier() {
        let item = ModelCatalogItem(
            displayName: "Ultra Only",
            family: .mlxCommunity,
            variant: "MLX 4-bit \(UUID().uuidString)",
            summary: "",
            parameterSize: "12B",
            quantization: "MLX 4-bit",
            diskSize: "~8 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/ultra-only",
            minimumTier: .ultra
        )

        XCTAssertEqual(
            ModelInstallGuard.unsupportedTierMessage(for: item, currentTier: .pro),
            "Needs Ultra (12 GB+)"
        )
        XCTAssertNil(ModelInstallGuard.unsupportedTierMessage(for: item, currentTier: .ultra))
    }

    func test_modelInstallGuardRequiresConsentForHighResidentMemory() {
        let item = ModelCatalogItem(
            displayName: "Memory Heavy",
            family: .mlxCommunity,
            variant: "MLX 4-bit \(UUID().uuidString)",
            summary: "",
            parameterSize: "8B",
            quantization: "MLX 4-bit",
            diskSize: "~5 GB",
            contextWindow: "128K",
            runtimeType: .mlx,
            mlxModelID: "mlx-community/memory-heavy",
            minimumTier: .pro
        )

        let consent = ModelInstallGuard.memoryConsentRequirement(for: item, currentTier: .pro)

        XCTAssertNotNil(consent)
        XCTAssertGreaterThan(consent?.required ?? 0, consent?.available ?? .infinity)
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

    func test_gemma4CatalogUsesLiteRTLMImageRuntime() {
        let gemmaItems = MockCatalogData.items.filter {
            $0.displayName.hasPrefix("Gemma 4")
                && $0.runtimeType == .liteRTLM
                && $0.supportsVision
        }

        XCTAssertEqual(gemmaItems.count, 2)
        for item in gemmaItems {
            XCTAssertTrue(item.sourceInputCategories.contains(.image))
            XCTAssertTrue(item.sourceInputCategories.contains(.video))
            XCTAssertTrue(item.sourceInputCategories.contains(.audio))
            XCTAssertTrue(item.supportsVision)
            XCTAssertTrue(item.runtimeInputCategories.contains(.image))
            XCTAssertFalse(item.runtimeInputCategories.contains(.video))
            XCTAssertFalse(item.runtimeInputCategories.contains(.audio))
            XCTAssertTrue(item.inputCategoriesDifferByRuntime)
            XCTAssertNotNil(item.downloadURL)
        }
    }

    func test_catalogIncludesCuratedGemmaFamilyModels() {
        let expectedIDs: Set<String> = [
            "litert-community/gemma-4-E2B-it-litert-lm",
            "litert-community/gemma-4-E4B-it-litert-lm",
            "mlx-community/gemma-2-2b-it-4bit",
            "mlx-community/gemma-3-1b-it-4bit"
        ]
        let actualIDs = Set(MockCatalogData.items
            .filter { $0.family == .gemma }
            .compactMap(Self.catalogSourceID)
        )

        XCTAssertTrue(
            expectedIDs.isSubset(of: actualIDs),
            "Missing Gemma catalog IDs: \(expectedIDs.subtracting(actualIDs))"
        )

        let unverifiedRecommended = MockCatalogData.items.filter {
            $0.family == .gemma && $0.auditVerdict != .green && $0.recommendedForIPhone
        }
        XCTAssertTrue(unverifiedRecommended.isEmpty)
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

    func test_catalogFeaturesMajorOpenSourceProviderFamilies() {
        let expectedModelIDsByFamily: [ModelCatalogItem.ModelFamily: Set<String>] = [
            .gemma: [
                "litert-community/gemma-4-E2B-it-litert-lm",
                "litert-community/gemma-4-E4B-it-litert-lm",
                "mlx-community/gemma-2-2b-it-4bit",
                "mlx-community/gemma-3-1b-it-4bit"
            ],
            .llama: [
                "mlx-community/Llama-3.2-1B-Instruct-4bit"
            ],
            .phi: [
                "mlx-community/Phi-3.5-mini-instruct-4bit"
            ],
            .deepSeek: [
                "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit"
            ],
            .mistral: [
                "mlx-community/Ministral-3-3B-Instruct-2512-4bit"
            ],
            .smolLM: [
                "mlx-community/SmolLM3-3B-4bit"
            ]
        ]

        for (family, expectedIDs) in expectedModelIDsByFamily {
            let actualIDs = Set(MockCatalogData.items
                .filter { $0.family == family }
                .compactMap(Self.catalogSourceID)
            )
            XCTAssertTrue(
                expectedIDs.isSubset(of: actualIDs),
                "Missing featured \(family.rawValue) model IDs: \(expectedIDs.subtracting(actualIDs))"
            )
        }
    }

    private static func catalogSourceID(for item: ModelCatalogItem) -> String? {
        if let mlxModelID = item.mlxModelID {
            return mlxModelID
        }

        guard let downloadURL = item.downloadURL,
              let range = downloadURL.absoluteString.range(of: #"huggingface\.co/([^/]+/[^/]+)/"#, options: .regularExpression)
        else {
            return nil
        }
        let matched = String(downloadURL.absoluteString[range])
        return matched
            .replacingOccurrences(of: "huggingface.co/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

    func test_shippedCatalogExcludesUnsupportedOrRedModels() {
        let nonWorkingItems = MockCatalogData.items.filter { item in
            item.runtimeStatus == .unsupported
                || {
                    if case .red = item.auditVerdict { return true }
                    return false
                }()
        }

        XCTAssertTrue(
            nonWorkingItems.isEmpty,
            "Shipped catalog must not include unsupported or red-audited models: \(nonWorkingItems.map(\.displayName).joined(separator: ", "))"
        )
    }

    func test_ggufVisionFamiliesAreTextOnlyInAppRuntime() {
        let ggufVisionFamilyItems = MockCatalogData.items.filter { item in
            item.runtimeType == .gguf && item.sourceSupportsVision
        }

        XCTAssertTrue(ggufVisionFamilyItems.allSatisfy { !$0.runtimeInputCategories.contains(.image) })
    }

#if canImport(MLXLLM) && !targetEnvironment(simulator)
    func test_mlxRuntimeUsesTextFactoryForBundledVLMFamiliesWithoutImageInput() async {
        let vlmModelIDs = [
            "mlx-community/paligemma-3b-mix-448-8bit",
            "mlx-community/Qwen2-VL-2B-Instruct-4bit",
            "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            "mlx-community/Qwen25VL-3B-Instruct-4bit",
            "mlx-community/Qwen3-VL-4B-Instruct-8bit",
            "mlx-community/Qwen3VL-4B-Instruct-8bit",
            "mlx-community/Qwen3.5-0.8B-4bit",
            "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit",
            "mlx-community/idefics3-8b-4bit",
            "mlx-community/gemma-3-4b-it-4bit",
            "mlx-community/gemma-4-e4b-it-4bit",
            "mlx-community/gemma-4-e2b-it-4bit",
            "mlx-community/SmolVLM2-500M-Video-Instruct-mlx",
            "HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx",
            "mlx-community/FastVLM-0.5B-4bit",
            "mlx-community/llava-qwen2-7b-4bit",
            "mlx-community/pixtral-12b-4bit",
            "mlx-community/Mistral-3-3B-4bit",
            "mlx-community/LFM2.5-VL-1.6B-4bit",
            "mlx-community/glm-ocr-2b-4bit"
        ]

        for modelID in vlmModelIDs {
            let usesVisionFactory = await MLXRuntime.shared.shouldUseVisionFactory(
                modelID: modelID,
                supportsVision: true,
                imageData: nil
            )
            XCTAssertFalse(usesVisionFactory, "Expected text-only prompts to avoid VLM factory for \(modelID)")
        }
    }

    func test_mlxRuntimeUsesVisionFactoryForImageInput() async {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let usesVisionFactory = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: "mlx-community/gemma-4-e2b-it-4bit",
            supportsVision: true,
            imageData: imageData
        )

        XCTAssertTrue(usesVisionFactory, "Expected image prompts to use VLM factory")
    }

    func test_mlxRuntimeDoesNotUseVisionFactoryForImageInputOnTextOnlyModel() async {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let usesVisionFactory = await MLXRuntime.shared.shouldUseVisionFactory(
            modelID: "mlx-community/Qwen3-1.7B-4bit",
            supportsVision: false,
            imageData: imageData
        )

        XCTAssertFalse(usesVisionFactory, "Expected text-only models to avoid VLM factory even when image data is present")
    }

    func test_mlxRuntimeDoesNotUseVisionFactoryForTextOnlyModels() async {
        let textModelIDs = [
            "mlx-community/gemma-4-e2b-it-4bit",
            "mlx-community/Qwen3-1.7B-4bit",
            "mlx-community/LFM2.5-350M-6bit"
        ]

        for modelID in textModelIDs {
            let usesVisionFactory = await MLXRuntime.shared.shouldUseVisionFactory(
                modelID: modelID,
                supportsVision: false,
                imageData: nil
            )
            XCTAssertFalse(usesVisionFactory, "Expected LLM factory for \(modelID)")
        }
    }
#endif
}
