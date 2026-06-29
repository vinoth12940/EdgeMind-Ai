// EdgeMindAiTests/DeviceTierTests.swift
import XCTest
@testable import EdgeMindAi

final class DeviceTierTests: XCTestCase {

    func test_iPhone12Family_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,1"), .compact) // 12 mini (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,2"), .compact) // 12       (4 GB)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,3"), .compact) // 12 Pro   (6 GB, still A14 → compact)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone13,4"), .compact) // 12 Pro Max
    }

    func test_iPhoneSE3_classifiesAsCompact() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,6"), .compact)
    }

    func test_iPhone13_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,5"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,2"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone14,3"), .standard)
    }

    func test_iPhone15_nonPro_classifiesAsStandard() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,4"), .standard)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone15,5"), .standard)
    }

    func test_iPhone15Pro_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,1"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone16,2"), .pro)
    }

    func test_iPhone16Series_classifiesAsPro() {
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,1"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,2"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,3"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPhone17,4"), .pro)
    }

    func test_unknownDeviceDefaultsToPro() {
        // Simulator, iPad, future iPhone: lean toward allowing more.
        XCTAssertEqual(DeviceTier.classify(machine: "x86_64"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "arm64"), .pro)
        XCTAssertEqual(DeviceTier.classify(machine: "iPad13,1"), .pro)
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
}
