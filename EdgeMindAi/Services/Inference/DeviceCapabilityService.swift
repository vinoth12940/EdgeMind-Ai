import Darwin
import Foundation

/// Device hardware detection for safe inference parameter selection.
enum DeviceCapabilityService {

    /// Returns the safe KV-cache context window (n_ctx) based on device RAM tier.
    ///
    /// Smaller n_ctx = smaller KV cache = fewer crashes on RAM-constrained devices.
    /// KV cache memory is proportional to n_ctx × model layers × head size.
    /// A 7B Q4_K_M model at n_ctx=8192 creates ~1 GB of KV cache, which exceeds
    /// available RAM on iPhone 12 (4 GB) when combined with ~4.3 GB model weights.
    static func contextSize() -> Int32 {
        contextSize(for: machineModel())
    }

    /// Testable overload — pass a known machine string to verify tier selection.
    static func contextSize(for machine: String) -> Int32 {
        // iPhone 12 series — A14 Bionic, 4 GB RAM: "iPhone13,x"
        if machine.hasPrefix("iPhone13,") { return 2048 }
        // iPhone 13 / iPhone 14 — A15/A16, 4–6 GB RAM: "iPhone14,x", "iPhone15,x"
        if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone15,") { return 4096 }
        // iPhone 15+ (A17/A18), iPad, and simulator — 6–8+ GB RAM
        return 8192
    }

    /// Returns true if the device has A15 Bionic or newer and benefits from flash attention.
    ///
    /// Flash attention cuts peak memory during prefill and improves throughput ~20–30%
    /// on A15+. On A14 it may be unstable or offer no benefit.
    static func supportsFlashAttention() -> Bool {
        supportsFlashAttention(for: machineModel())
    }

    /// Testable overload — pass a known machine string to verify flash attn selection.
    static func supportsFlashAttention(for machine: String) -> Bool {
        // iPhone 12 series is A14 — flash attention disabled for stability
        return !machine.hasPrefix("iPhone13,")
    }

    /// Returns the raw hw.machine sysctl string, e.g. "iPhone16,1".
    static func machineModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
