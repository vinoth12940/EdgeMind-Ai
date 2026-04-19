// LocalAIEdgeAppTests/RuntimeProfileTests.swift
import XCTest
@testable import LocalAIEdgeApp

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
        let catalog = MockCatalogData.items.filter { $0.runtimeType == .mlx }
        for item in catalog {
            let p = store.profile(for: item.id)
            XCTAssertNotNil(p, "Missing profile for \(item.displayName) (\(item.id))")
        }
    }

    func test_missingProfileReturnsNil() {
        let store = RuntimeProfileStore()
        XCTAssertNil(store.profile(for: UUID()))
    }

    func test_resolverPrefersProfileForRuntimeBehavior() {
        let item = MockCatalogData.items.first { $0.displayName == "LFM2.5 VL 1.6B (MLX)" }!
        let store = RuntimeProfileStore()
        let resolved = ModelRuntimeResolver.resolve(catalog: item, store: store)
        // Catalog claims vision: true (supportsVision), profile should confirm
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
            overrideLoader: { [override] }
        )
        let resolved = store.profile(for: id)
        XCTAssertEqual(resolved?.auditVerdict, .green)
        XCTAssertEqual(resolved?.verifiedThinking, .qwenNative)
        XCTAssertEqual(resolved?.recommendedMaxTokens, 2048)
        XCTAssertTrue(resolved?.knownLeakTokens.contains("<|override|>") == true)
    }

    /// A compile-time safeguard: in Release builds the override path returns [] by
    /// construction (`#else` branch). The test cannot prove the `#if` is in place, but
    /// it does lock in the injectable contract so a later refactor that drops the
    /// overrideLoader parameter trips this test and forces a code review.
    func test_storeAcceptsInjectedOverrideLoader() {
        // Pure signature check — if this compiles, the injection hook exists.
        _ = RuntimeProfileStore(bundleLoader: { [] }, overrideLoader: { [] })
    }

    func test_bundledJSONResolvesFromAppBundle() throws {
        // Belt-and-braces check: the actual Bundle.main URL lookup used by the default
        // loader path must succeed. Otherwise the resource did not make it into the app.
        let url = Bundle(for: RuntimeProfileTests.self).url(forResource: "RuntimeProfiles", withExtension: "json")
            ?? Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json")
        XCTAssertNotNil(url, "RuntimeProfiles.json is not in the built app bundle. Run xcodegen generate + rebuild.")
    }
}
