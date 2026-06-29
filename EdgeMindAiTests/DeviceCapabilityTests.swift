import XCTest
@testable import EdgeMindAi

final class DeviceCapabilityTests: XCTestCase {

    func testNCtxSelectionIPhone12() {
        // iPhone 12 series (A14 Bionic, 4 GB RAM) must use 2048 to avoid KV cache OOM
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone13,1"), 2048)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone13,4"), 2048)
    }

    func testNCtxSelectionIPhone13And14() {
        // iPhone 13 (A15) and iPhone 14 (A15/A16), 4–6 GB RAM → 4096 is safe
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone14,2"), 4096)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone15,2"), 4096)
    }

    func testNCtxSelectionIPhone15AndNewer() {
        // iPhone 15+ (A17/A18), 6–8 GB RAM → full 8192 context
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone16,1"), 8192)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPhone17,3"), 8192)
    }

    func testNCtxSelectionIPad() {
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "iPad13,4"), 8192)
    }

    func testNCtxSelectionSimulator() {
        // Simulator returns empty string → falls through to 8192 (development machine has plenty of RAM)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: ""), 8192)
        XCTAssertEqual(DeviceCapabilityService.contextSize(for: "arm64"), 8192)
    }

    func testFlashAttentionDisabledOnA14() {
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone13,1"))
        XCTAssertFalse(DeviceCapabilityService.supportsFlashAttention(for: "iPhone13,4"))
    }

    func testFlashAttentionEnabledOnA15AndNewer() {
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPhone14,2"))
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPhone16,1"))
        XCTAssertTrue(DeviceCapabilityService.supportsFlashAttention(for: "iPad13,4"))
    }

    func testLiveDeviceReturnsSaneValues() {
        let nCtx = DeviceCapabilityService.contextSize()
        XCTAssertTrue([2048, 4096, 8192].contains(nCtx), "contextSize() returned unexpected value \(nCtx)")
    }
}
