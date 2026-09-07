import XCTest
@testable import EdgeMindAi

final class DeviceCapabilityTests: XCTestCase {

    func testNCtxSelectionCompactDevices() {
        // iPhone 10 (A11), iPhone XR/XS (A12), iPhone 11 (A13), iPhone 12 (A14) — safe 2048
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone10,3"), 2048) // iPhone X
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone11,8"), 2048) // iPhone XR
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone12,1"), 2048) // iPhone 11
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone12,8"), 2048) // iPhone SE 2
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone13,1"), 2048) // iPhone 12 mini
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone13,4"), 2048) // iPhone 12 Pro Max

        // iPhone 13 (A15), iPhone 13 mini (A15), and SE 3 (A15) — 4 GB RAM -> safe 2048
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,4"), 2048) // iPhone 13 mini
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,5"), 2048) // iPhone 13
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,6"), 2048) // iPhone SE 3

        // Standard iPads and pre-A15 iPad Pros (3–4 GB RAM) — safe 2048
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad7,11"), 2048)  // iPad 7th gen
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad8,1"), 2048)   // iPad Pro 11" 1st gen (A12X)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad11,1"), 2048)  // iPad mini 5th gen
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad12,1"), 2048)  // iPad 9th gen
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad13,1"), 2048)  // iPad Air 4th gen
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad13,18"), 2048) // iPad 10th gen
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad14,1"), 2048)  // iPad mini 6th gen
    }

    func testNCtxSelectionIPhone13And14() {
        // iPhone 13 Pro (A15) and iPhone 14 (A15/A16), 6 GB RAM → 4096 is safe
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,2"), 4096)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,3"), 4096)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,7"), 4096)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone15,2"), 4096)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone15,4"), 4096)
    }

    func testNCtxSelectionIPhone15AndNewer() {
        // iPhone 15 Pro, iPhone 16 (A17/A18), 8 GB RAM → full 8192 context
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone16,1"), 8192)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone17,3"), 8192)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone18,1"), 8192)
    }

    func testNCtxSelectionUltra() {
        // iPhone 17 Pro Max (12 GB RAM) → 16384 context
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone18,4"), 16384)
    }

    func testNCtxSelectionIPad() {
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad13,4"), 8192)
    }

    func testNCtxSelectionSimulator() {
        // Simulator returns empty string → falls through to 8192 (development machine has plenty of RAM)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: ""), 8192)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "arm64"), 8192)
    }

    func testFlashAttentionDisabledOnPreA15() {
        // A11–A14 iPhones
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone10,3")) // A11
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone11,2")) // A12
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone12,1")) // A13
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone13,1")) // A14
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone13,4")) // A14

        // A10–A14 iPads
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad7,11"))  // A10
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad8,1"))   // A12X
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad11,1"))  // A12
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad12,1"))  // A13
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad13,1"))  // A14 Air 4
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPad13,18")) // A14 10th gen
    }

    func testFlashAttentionEnabledOnA15AndNewer() {
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPhone14,2"))
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPhone16,1"))
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPhone17,1"))
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPad13,4"))
    }

    func testLiveDeviceReturnsSaneValues() {
        let nCtx = DeviceCapabilityService.contextSize()
        XCTAssertTrue([2048, 4096, 8192, 16384].contains(nCtx), "contextSize() returned unexpected value \(nCtx)")
    }
}
