// EdgeMindAiTests/MemoryCoordinatorAndGuardStressTests.swift
import XCTest
@testable import EdgeMindAi

final class MemoryCoordinatorAndGuardStressTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await RuntimeMemoryCoordinator.releaseAll()
    }

    override func tearDown() async throws {
        await RuntimeMemoryCoordinator.releaseAll()
        try await super.tearDown()
    }

    // MARK: - 1. Concurrency & Stress Tests for RuntimeMemoryCoordinator

    func test_concurrentAccessToActiveRuntime_isThreadSafe() async {
        // Stress test reading activeRuntime concurrently while multiple tasks update it.
        // We verify that no data race crash or lock deadlock occurs under heavy concurrent load.
        let iterationCount = 200

        await withTaskGroup(of: Void.self) { group in
            // Task group 1: Readers
            for _ in 0..<iterationCount {
                group.addTask {
                    _ = RuntimeMemoryCoordinator.activeRuntime
                }
            }

            // Task group 2: Writers toggling runtimes
            for i in 0..<50 {
                let runtime: ModelCatalogItem.RuntimeType = (i % 3 == 0) ? .mlx : ((i % 3 == 1) ? .liteRTLM : .gguf)
                group.addTask {
                    await RuntimeMemoryCoordinator.prepareForRuntime(runtime)
                }
            }

            // Task group 3: Releasers
            for _ in 0..<20 {
                group.addTask {
                    await RuntimeMemoryCoordinator.releaseAll()
                }
            }
        }

        // Clean up and assert final release
        await RuntimeMemoryCoordinator.releaseAll()
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime, "activeRuntime should be nil after releaseAll()")
    }

    func test_sequentialRuntimeSwitching_enforcesSingleActiveRuntime() async {
        let runtimes: [ModelCatalogItem.RuntimeType] = [.gguf, .mlx, .liteRTLM, .foundationModels, .gguf]

        for runtime in runtimes {
            await RuntimeMemoryCoordinator.prepareForRuntime(runtime)
            XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, runtime, "Active runtime should transition to \(runtime)")
        }

        await RuntimeMemoryCoordinator.releaseAll()
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime)
    }

    func test_releaseAfterAudit_onlyClearsMatchingRuntime() async {
        await RuntimeMemoryCoordinator.prepareForRuntime(.mlx)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .mlx)

        // Attempting to release a non-active runtime should NOT clear the active runtime
        await RuntimeMemoryCoordinator.releaseAfterAudit(.gguf)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .mlx, "Releasing .gguf should not affect active .mlx runtime")

        // Releasing matching runtime should clear it
        await RuntimeMemoryCoordinator.releaseAfterAudit(.mlx)
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime, "Releasing active .mlx should clear activeRuntime to nil")
    }

    // MARK: - 2. Eviction & Backgrounding Verification

    func test_releaseAll_evictsAllRuntimeState() async {
        await RuntimeMemoryCoordinator.prepareForRuntime(.mlx)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .mlx)

        await RuntimeMemoryCoordinator.releaseAll()
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime)

        // Calling releaseAll multiple times consecutively should be idempotent and not deadlock
        await RuntimeMemoryCoordinator.releaseAll()
        await RuntimeMemoryCoordinator.releaseAll()
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime)
    }

    // MARK: - 3. AvailableMemoryGuard & Headroom Math Verification

    func test_availableMemoryBytes_returnsPositiveHeadroom() {
        let bytes = AvailableMemoryGuard.availableMemoryBytes()
        XCTAssertGreaterThan(bytes, 0, "availableMemoryBytes should return a positive value")

        let gb = AvailableMemoryGuard.availableMemoryGB()
        XCTAssertGreaterThan(gb, 0.0, "availableMemoryGB should return positive headroom")
    }

    func test_estimatedResidentGB_calculation() {
        // Test estimatedResidentGB across model configurations
        let compactTier = DeviceTier.compact
        XCTAssertEqual(compactTier.safeContextTokens, 2048)

        // Find a representative catalog item
        guard let gemmaItem = MockCatalogData.items.first(where: { $0.displayName.contains("Gemma") }) else {
            XCTFail("Missing Gemma model in catalog")
            return
        }

        let estimatedCompact = gemmaItem.estimatedResidentGB(contextTokens: compactTier.safeContextTokens)
        XCTAssertGreaterThan(estimatedCompact, 0.5, "Resident memory estimate should be non-trivial")

        let ultraTier = DeviceTier.ultra
        let estimatedUltra = gemmaItem.estimatedResidentGB(contextTokens: ultraTier.safeContextTokens)
        XCTAssertGreaterThanOrEqual(estimatedUltra, estimatedCompact, "Ultra tier (16k context) should estimate >= compact tier (2k context)")
    }

    func test_checkMemoryHeadroom_simulatorBehavior() {
        // On simulator, checkMemoryHeadroom returns nil by design
        guard let model = MockCatalogData.items.first else {
            XCTFail("Catalog is empty")
            return
        }

        #if targetEnvironment(simulator)
        let alert = AvailableMemoryGuard.checkMemoryHeadroom(for: model)
        XCTAssertNil(alert, "In simulator environment, checkMemoryHeadroom should return nil")
        #endif
    }
}
