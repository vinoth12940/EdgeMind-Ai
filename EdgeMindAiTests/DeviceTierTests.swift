// EdgeMindAiTests/DeviceTierTests.swift
import XCTest
@testable import EdgeMindAi

final class DeviceTierTests: XCTestCase {

    func test_iPhone10Family_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone10,1"), .compact) // iPhone 8
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone10,2"), .compact) // iPhone 8 Plus
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone10,3"), .compact) // iPhone X
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone10,6"), .compact) // iPhone X
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone11,2"), .compact) // iPhone XS
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone11,4"), .compact) // iPhone XS Max
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone11,6"), .compact) // iPhone XS Max
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone11,8"), .compact) // iPhone XR
    }

    func test_iPhone11Family_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone12,1"), .compact) // iPhone 11
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone12,3"), .compact) // iPhone 11 Pro
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone12,5"), .compact) // iPhone 11 Pro Max
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone12,8"), .compact) // iPhone SE 2
    }

    func test_iPhone12Family_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,1"), .compact) // 12 mini (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,2"), .compact) // 12       (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,3"), .compact) // 12 Pro   (6 GB, still A14 → compact)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,4"), .compact) // 12 Pro Max
    }

    func test_iPhone13_and_Mini_and_SE3_classifyAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,4"), .compact) // iPhone 13 mini (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,5"), .compact) // iPhone 13      (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,6"), .compact) // iPhone SE 3    (4 GB)
    }

    func test_iPhone13Pro_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,2"), .standard) // iPhone 13 Pro     (6 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,3"), .standard) // iPhone 13 Pro Max (6 GB)
    }

    func test_iPhone14Series_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,7"), .standard) // iPhone 14
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,8"), .standard) // iPhone 14 Plus
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,2"), .standard) // iPhone 14 Pro
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,3"), .standard) // iPhone 14 Pro Max
    }

    func test_iPhone15_nonPro_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,4"), .standard) // iPhone 15
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,5"), .standard) // iPhone 15 Plus
    }

    func test_iPhone15Pro_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,1"), .pro) // iPhone 15 Pro
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,2"), .pro) // iPhone 15 Pro Max
    }

    func test_iPhone16Series_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,1"), .pro) // iPhone 16 Pro
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,2"), .pro) // iPhone 16 Pro Max
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,3"), .pro) // iPhone 16
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,4"), .pro) // iPhone 16 Plus
    }

    func test_iPhone17Series_classifiesAsProOrUltra() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone18,1"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone18,2"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone18,3"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone18,4"), .ultra) // iPhone 17 Pro Max (12 GB)
    }

    func test_standardIPads_classifyAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPad6,11"), .compact)  // iPad 5th gen
        XCTAssertEqual(DeviceTier.classify(machine: "iPad7,5"), .compact)   // iPad 6th gen
        XCTAssertEqual(DeviceTier.classify(machine: "iPad7,11"), .compact)  // iPad 7th gen (3 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad8,1"), .compact)   // iPad Pro 11" 1st gen (A12X, 4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad11,1"), .compact)  // iPad mini 5th gen (3 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad11,3"), .compact)  // iPad Air 3rd gen (3 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad11,6"), .compact)  // iPad 8th gen (3 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad12,1"), .compact)  // iPad 9th gen (3 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,1"), .compact)  // iPad Air 4th gen (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,18"), .compact) // iPad 10th gen (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad14,1"), .compact)  // iPad mini 6th gen (4 GB)
    }

    func test_mSeriesIPads_classifyAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,4"), .pro)  // iPad Pro 11" 3rd gen (M1)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,16"), .pro) // iPad Air 5th gen (M1)
    }

    func test_unknownDeviceDefaultsToPro() {
        // Simulator, future architecture: lean toward allowing more.
        XCTAssertEqual(DeviceTier.classify(machine: "x86_64"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "arm64"), .pro)
    }

    func test_physicalMemoryClassification() {
        let gb: UInt64 = 1024 * 1024 * 1024
        // iPhone 16 with 8GB -> pro
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,1", physicalMemoryBytes: 8 * gb), .pro)
        // iPhone 17 Pro Max with 12GB -> ultra
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone18,4", physicalMemoryBytes: 12 * gb), .ultra)
        // iPhone 14 with 6GB -> standard
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,7", physicalMemoryBytes: 6 * gb), .standard)
        // A14 device with 6GB is capped at compact
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,3", physicalMemoryBytes: 6 * gb), .compact)
        // iPhone 13 with 4GB -> compact
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,5", physicalMemoryBytes: 4 * gb), .compact)
        // iPad Pro A12X with 4GB -> compact
        XCTAssertEqual(DeviceTier.classify(machine: "iPad8,1", physicalMemoryBytes: 4 * gb), .compact)
    }

    func test_budgets() {
        XCTAssertEqual(DeviceTier.compact.usableWeightGB, 1.2, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.standard.usableWeightGB, 2.2, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.pro.usableWeightGB, 4.5, accuracy: 0.01)
        XCTAssertEqual(DeviceTier.ultra.usableWeightGB, 7.0, accuracy: 0.01)
    }

    func test_ordering() {
        XCTAssertLessThan(DeviceTier.compact, DeviceTier.standard)
        XCTAssertLessThan(DeviceTier.standard, DeviceTier.pro)
        XCTAssertLessThan(DeviceTier.pro, DeviceTier.ultra)
    }

    func test_runtimeMemoryCoordinator_mutualExclusion() async {
        await RuntimeMemoryCoordinator.prepareForRuntime(.mlx)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .mlx)

        await RuntimeMemoryCoordinator.prepareForRuntime(.liteRTLM)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .liteRTLM)

        await RuntimeMemoryCoordinator.prepareForRuntime(.gguf)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .gguf)

        await RuntimeMemoryCoordinator.releaseAfterAudit(.gguf)
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime)

        await RuntimeMemoryCoordinator.prepareForRuntime(.foundationModels)
        XCTAssertEqual(RuntimeMemoryCoordinator.activeRuntime, .foundationModels)

        await RuntimeMemoryCoordinator.releaseAll()
        XCTAssertNil(RuntimeMemoryCoordinator.activeRuntime)
    }
}
