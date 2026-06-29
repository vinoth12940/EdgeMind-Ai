// EdgeMindAiTests/RuntimeProfileTests.swift
import XCTest
@testable import EdgeMindAi

final class RuntimeProfileTests: XCTestCase {

    func test_verdictRoundTrip_green() throws {
        let v = Verdict.green
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(Verdict.self, from: data)
        XCTAssertEqual(decoded, .green)
    }

    func test_verdictRoundTrip_yellow() throws {
        let v = Verdict.yellow("pending-audit")
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(Verdict.self, from: data)
        XCTAssertEqual(decoded, .yellow("pending-audit"))
    }

    func test_profileRoundTrip() throws {
        let profile = RuntimeProfile(
            catalogID: UUID(),
            verifiedThinking: .qwenNative,
            verifiedToolCalling: .xmlToolCall,
            verifiedVision: .none,
            knownLeakTokens: ["<|im_end|>"],
            recommendedMaxTokens: 1024,
            auditedAt: "2026-04-19T08:00:00Z",
            auditVerdict: .green
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(RuntimeProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func test_bundledJSONLoads() throws {
        let store = RuntimeProfileStore()
        for item in MockCatalogData.items where item.primaryUse == .chat {
            let p = store.profile(for: item.id)
            XCTAssertNotNil(p, "Missing profile for \(item.displayName) (\(item.id))")
        }
    }

    func test_bundledProfilesEnableCatalogRuntimeCapabilities() throws {
        let store = RuntimeProfileStore()
        for item in MockCatalogData.items where item.primaryUse == .chat {
            let resolved = ModelRuntimeResolver.resolve(catalog: item, store: store)
            if item.supportsToolCalling {
                XCTAssertNotNil(resolved.tools, "Missing tool-call profile for \(item.displayName)")
            }
            if item.isThinkingModel {
                XCTAssertNotNil(resolved.thinking, "Missing thinking profile for \(item.displayName)")
            }
            if item.supportsVision && item.auditVerdict.isGreen {
                XCTAssertEqual(resolved.vision, .imageAndText, "Missing image runtime profile for \(item.displayName)")
            } else if item.sourceSupportsVision && resolved.vision != .imageAndText {
                XCTAssertEqual(resolved.vision, .textOnlyInputs, "Source-vision model should be profiled as text-only when the app runtime is not image-verified")
            }
        }
    }

    func test_gemma4VisionRuntimeUsesLiteRTLMImagePath() throws {
        let store = RuntimeProfileStore()
        let gemmaItems = MockCatalogData.items.filter {
            $0.displayName.hasPrefix("Gemma 4")
                && $0.runtimeType == .liteRTLM
                && $0.supportsVision
        }

        XCTAssertEqual(gemmaItems.count, 1)
        for item in gemmaItems {
            let resolved = ModelRuntimeResolver.resolve(catalog: item, store: store)
            XCTAssertTrue(item.sourceSupportsVision)
            XCTAssertFalse(item.sourceSupportsVideo)
            XCTAssertFalse(item.sourceSupportsAudio)
            XCTAssertTrue(item.supportsVision)
            XCTAssertEqual(resolved.vision, .imageAndText)
            XCTAssertFalse(resolved.isMismatch)
            XCTAssertEqual(resolved.tools, .gemmaNativeToolCall)
            XCTAssertFalse(resolved.verdict.isRed)
        }
    }

    func test_bundledJSONDoesNotContainStaleCatalogIDs() throws {
        let url = try XCTUnwrap(
            Bundle(for: RuntimeProfileTests.self).url(forResource: "RuntimeProfiles", withExtension: "json")
                ?? Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json")
        )
        let profiles = try JSONDecoder().decode([RuntimeProfile].self, from: Data(contentsOf: url))
        let catalogIDs = Set(MockCatalogData.items.map(\.id))
        for profile in profiles {
            XCTAssertTrue(catalogIDs.contains(profile.catalogID), "Stale profile for removed catalog ID \(profile.catalogID)")
        }
    }

    func test_missingProfileReturnsNil() {
        let store = RuntimeProfileStore()
        XCTAssertNil(store.profile(for: UUID()))
    }

    func test_resolverPrefersProfileForRuntimeBehavior() {
        let item = MockCatalogData.items.first { $0.runtimeType == .mlx }!
        let injected = RuntimeProfile(
            catalogID: item.id,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .imageAndText,
            knownLeakTokens: [],
            recommendedMaxTokens: 1024,
            auditedAt: "2026-04-19T10:00:00Z",
            auditVerdict: .green
        )
        let store = RuntimeProfileStore(bundleLoader: { [injected] }, overrideLoader: { [] })
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: store)
        XCTAssertEqual(resolved.vision, .imageAndText)
    }

    func test_resolverFallsBackToSafeMinimumWhenNoProfile() {
        let item = MockCatalogData.items.first!
        let emptyStore = RuntimeProfileStore(bundleLoader: { [] })
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: emptyStore)
        XCTAssertEqual(resolved.vision, .none)
        XCTAssertNil(resolved.thinking)
        XCTAssertNil(resolved.tools)
    }

    func test_overrideLoaderShadowsBundled() {
        let id = UUID()
        let bundled = RuntimeProfile(
            catalogID: id,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .none,
            knownLeakTokens: [],
            recommendedMaxTokens: 512,
            auditedAt: "",
            auditVerdict: .yellow("pending-audit")
        )
        let override = RuntimeProfile(
            catalogID: id,
            verifiedThinking: .qwenNative,
            verifiedToolCalling: .xmlToolCall,
            verifiedVision: .imageAndText,
            knownLeakTokens: ["<|override|>"],
            recommendedMaxTokens: 2048,
            auditedAt: "2026-04-19T09:00:00Z",
            auditVerdict: .green
        )
        let store = RuntimeProfileStore(
            bundleLoader: { [bundled] },
            overrideLoader: { [override] },
            overridePolicy: .enabled
        )
        let resolved = store.profile(for: id)
        XCTAssertEqual(resolved?.auditVerdict, .green)
        XCTAssertEqual(resolved?.verifiedThinking, .qwenNative)
        XCTAssertEqual(resolved?.recommendedMaxTokens, 2048)
        XCTAssertTrue(resolved?.knownLeakTokens.contains("<|override|>") == true)
    }

    func test_overrideLoaderIgnoredWhenDisabled() {
        let id = UUID()
        let bundled = RuntimeProfile(
            catalogID: id,
            verifiedThinking: nil,
            verifiedToolCalling: nil,
            verifiedVision: .none,
            knownLeakTokens: [],
            recommendedMaxTokens: 512,
            auditedAt: "",
            auditVerdict: .yellow("pending-audit")
        )
        let override = RuntimeProfile(
            catalogID: id,
            verifiedThinking: .qwenNative,
            verifiedToolCalling: .xmlToolCall,
            verifiedVision: .imageAndText,
            knownLeakTokens: ["<|override|>"],
            recommendedMaxTokens: 2048,
            auditedAt: "2026-04-19T09:00:00Z",
            auditVerdict: .green
        )
        let store = RuntimeProfileStore(
            bundleLoader: { [bundled] },
            overrideLoader: { [override] },
            overridePolicy: .disabled
        )

        let resolved = store.profile(for: id)
        XCTAssertEqual(resolved?.auditVerdict, .yellow("pending-audit"))
        XCTAssertNil(resolved?.verifiedThinking)
        XCTAssertEqual(resolved?.recommendedMaxTokens, 512)
        XCTAssertFalse(resolved?.knownLeakTokens.contains("<|override|>") == true)
    }

    /// A compile-time safeguard: in Release builds the override path returns [] by
    /// construction (`#else` branch). The test cannot prove the `#if` is in place, but
    /// it does lock in the injectable contract so a later refactor that drops the
    /// overrideLoader parameter trips this test and forces a code review.
    func test_storeAcceptsInjectedOverrideLoader() {
        // Pure signature check — if this compiles, the injection hook exists.
        _ = RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] }, overridePolicy: .disabled)
    }

    func test_bundledJSONResolvesFromAppBundle() throws {
        // Belt-and-braces check: the actual Bundle.main URL lookup used by the default
        // loader path must succeed. Otherwise the resource did not make it into the app.
        let url = Bundle(for: RuntimeProfileTests.self).url(forResource: "RuntimeProfiles", withExtension: "json")
            ?? Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json")
        XCTAssertNotNil(url, "RuntimeProfiles.json is not in the built app bundle. Run xcodegen generate + rebuild.")
    }
}
