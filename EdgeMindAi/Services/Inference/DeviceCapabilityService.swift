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
        Int32(DeviceTier.current().safeContextTokens)
    }

    /// Testable overload — pass a known machine string to verify tier selection.
    static func contextSize(for machine: String) -> Int32 {
        Int32(DeviceTier.classify(machine: machine).safeContextTokens)
    }

    /// Returns true if the device has A15 Bionic or newer and benefits from flash attention.
    ///
    /// Flash attention cuts peak memory during prefill and improves throughput ~20–30%
    /// on A15+. On A14 and older it may be unstable or offer no benefit.
    static func supportsFlashAttention() -> Bool {
        supportsFlashAttention(for: machineModel())
    }

    /// Testable overload — pass a known machine string to verify flash attn selection.
    static func supportsFlashAttention(for machine: String) -> Bool {
        // Pre-A15 chips (A10–A14 iPhones and iPads) do not support flash attention safely.
        // iPhones: iPhone 8/X (iPhone10,), XS/XR (iPhone11,), 11 (iPhone12,), 12 (iPhone13,).
        if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,") {
            return false
        }
        // Pre-A15 iPads: iPad 5th/6th/7th gen (iPad6,, iPad7,), iPad Pro A12X/Z (iPad8,),
        // iPad mini 5 / Air 3 / 8th gen (iPad11,), iPad 9th gen (iPad12,).
        if machine.hasPrefix("iPad6,") || machine.hasPrefix("iPad7,") || machine.hasPrefix("iPad8,") || machine.hasPrefix("iPad11,") || machine.hasPrefix("iPad12,") {
            return false
        }
        // A14 iPads: iPad Air 4 (iPad13,1–13,3) and iPad 10th gen (iPad13,18–13,19).
        // Note: M1 iPads (iPad13,4–13,11, iPad13,16–13,17) DO support flash attention safely.
        if machine.hasPrefix("iPad13,") {
            let isM1IPad = machine.hasPrefix("iPad13,4") || machine.hasPrefix("iPad13,5") || machine.hasPrefix("iPad13,6")
                || machine.hasPrefix("iPad13,7") || machine.hasPrefix("iPad13,8") || machine.hasPrefix("iPad13,9")
                || machine.hasPrefix("iPad13,10") || machine.hasPrefix("iPad13,11") || machine.hasPrefix("iPad13,16")
                || machine.hasPrefix("iPad13,17")
            if !isM1IPad {
                return false
            }
        }
        return true
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
