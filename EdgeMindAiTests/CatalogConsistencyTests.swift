import XCTest
@testable import EdgeMindAi

/// Invariants every catalog entry must satisfy so a model the user installs
/// actually loads, runs, and shows truthful information/category on its card.
/// RuntimeProfileTests covers catalog ↔ RuntimeProfiles.json capability sync;
/// this suite covers the catalog's own internal consistency.
final class CatalogConsistencyTests: XCTestCase {

    private let items = MockCatalogData.items

    func test_allCatalogIDsAreUnique() {
        var seen: [UUID: String] = [:]
        for item in items {
            if let existing = seen[item.id] {
                XCTFail("Duplicate catalog ID \(item.id): \(existing) and \(item.displayName) [\(item.variant)]")
            }
            seen[item.id] = item.displayName
        }
    }

    func test_runtimeTypeHasWorkingLoadPath() {
        for item in items {
            switch item.runtimeType {
            case .gguf:
                XCTAssertNotNil(item.downloadURL,
                    "\(item.displayName): .gguf model has no downloadURL — it can never be installed")
            case .mlx:
                XCTAssertNotNil(item.mlxModelID,
                    "\(item.displayName): .mlx model has no mlxModelID — MLXInferenceService cannot load it")
            case .liteRTLM:
                XCTAssertNotNil(item.downloadURL,
                    "\(item.displayName): .liteRTLM model has no downloadURL for its task bundle")
            case .foundationModels:
                XCTAssertNil(item.downloadURL,
                    "\(item.displayName): FoundationModels entries must not carry a downloadURL")
                XCTAssertNil(item.mlxModelID,
                    "\(item.displayName): FoundationModels entries must not carry an mlxModelID")
            }
        }
    }

    func test_visionClaimMatchesInputModes() {
        for item in items {
            if item.supportsVision {
                XCTAssertTrue(item.inputModes.contains(.image),
                    "\(item.displayName): supportsVision but .image missing from inputModes — user cannot attach an image")
                XCTAssertTrue(item.sourceSupportsVision,
                    "\(item.displayName): supportsVision without sourceSupportsVision — the weights have no vision encoder")
            } else {
                XCTAssertFalse(item.inputModes.contains(.image),
                    "\(item.displayName): accepts .image input but supportsVision is false — image prompts would fail at inference")
            }
        }
    }

    func test_redVerdictModelsAreNotRecommended() {
        for item in items where item.auditVerdict.isRed {
            XCTAssertNotEqual(item.runtimeStatus, .recommended,
                "\(item.displayName): red audit verdict but runtimeStatus .recommended")
            XCTAssertFalse(item.recommendedForIPhone,
                "\(item.displayName): red audit verdict but recommendedForIPhone")
        }
    }

    func test_contextWindowParsesForDownloadableModels() {
        for item in items where item.runtimeType != .foundationModels {
            XCTAssertGreaterThan(item.contextWindowTokenCount, 0,
                "\(item.displayName): contextWindow \"\(item.contextWindow)\" does not parse to a token count — budget math falls back blindly")
        }
    }

    /// The same model weights offered on multiple runtimes must not advertise
    /// contradictory context windows (e.g. Gemma 4 E2B showing 32K on LiteRT
    /// but 128K on MLX). Grouped by the base model name — the displayName up to
    /// the runtime suffix, e.g. "Gemma 4 E2B Instruct (MLX)" → "Gemma 4 E2B Instruct".
    /// (family + parameterSize is not unique: Gemma 2 2B vs Gemma 4 E2B are both
    /// gemma/2B but genuinely different models with different context windows.)
    func test_sameModelAcrossRuntimesAgreesOnContextWindow() {
        var byModel: [String: [(String, Int)]] = [:]
        for item in items where item.runtimeType != .foundationModels {
            let key = String(item.displayName.prefix(while: { $0 != "(" }))
                .trimmingCharacters(in: .whitespaces)
            byModel[key, default: []].append((item.displayName, item.contextWindowTokenCount))
        }
        for (_, entries) in byModel where entries.count > 1 {
            let counts = Set(entries.map(\.1))
            XCTAssertEqual(counts.count, 1,
                "Conflicting context windows for the same model across runtimes: \(entries)")
        }
    }
}
