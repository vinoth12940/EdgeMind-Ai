import Foundation

/// Classifies the device into a coarse RAM / compute bucket so the catalog
/// and download guard can hide or warn about models that will not run safely.
///
/// Tier boundaries come from iOS jetsam behavior: foreground apps are killed
/// around ~55–60% of physical RAM. `usableWeightGB` targets ~35% of total,
/// leaving room for KV cache, MLX GPU cache, vision tower, app heap, OS.
enum DeviceTier: String, Comparable, Codable, CaseIterable {
    case compact   // 4 GB devices: iPhone 12 family, SE 2/3, 13, 13 mini
    case standard  // 6 GB devices: iPhone 13 Pro, 14, 15 non-Pro
    case pro       // 8 GB devices: iPhone 15 Pro, 16, 17 non-Max
    case ultra     // 12 GB+ devices: iPhone 17 Pro Max, iPad M-series

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .compact:  return 0
        case .standard: return 1
        case .pro:      return 2
        case .ultra:    return 3
        }
    }

    /// Approximate resident memory budget for the model binary + KV cache + vision tower + heap.
    var usableWeightGB: Double {
        switch self {
        case .compact:  return 1.2
        case .standard: return 2.2
        case .pro:      return 4.5
        case .ultra:    return 7.0
        }
    }

    /// Conservative context-window size that the KV cache will actually allocate.
    /// Cataloged `contextWindow` strings (40K, 128K, 256K) are aspirational;
    /// this is what the runtime will actually use on the device.
    var safeContextTokens: Int {
        switch self {
        case .compact:  return 2048
        case .standard: return 4096
        case .pro:      return 8192
        case .ultra:    return 16384
        }
    }

    /// Soft threshold used by the audit runner's memory expectation.
    /// Tracks the jetsam "low memory" warning level, not the hard kill.
    var jetsamSoftLimitGB: Double {
        switch self {
        case .compact:  return 1.2
        case .standard: return 2.2
        case .pro:      return 4.5
        case .ultra:    return 7.0
        }
    }

    var displayName: String {
        switch self {
        case .compact:  return "Compact (4 GB)"
        case .standard: return "Standard (6 GB)"
        case .pro:      return "Pro (8 GB)"
        case .ultra:    return "Ultra (12 GB+)"
        }
    }

    /// Read-only classifier — combines physical memory (ground truth) with machine model.
    static func current() -> DeviceTier {
#if targetEnvironment(simulator)
        return .pro
#else
        classify(
            machine: DeviceCapabilityService.machineModel(),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
#endif
    }

    /// Testable — classify by machine model and optional physical memory bytes.
    static func classify(machine: String, physicalMemoryBytes: UInt64? = nil) -> DeviceTier {
        // If real physical memory is provided (e.g. on a live device),
        // check physical memory to avoid misclassifying older or unlisted devices.
        if let memory = physicalMemoryBytes, memory > 0 {
            // A14 and older devices (iPhone 13,x and lower, pre-A15 iPads, 4 GB A15 iPhones) are always capped at .compact
            // due to memory constraints and absence of modern hardware support.
            if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone13,")
                || machine == "iPhone14,4" || machine == "iPhone14,5" || machine == "iPhone14,6"
                || machine.hasPrefix("iPad6,") || machine.hasPrefix("iPad7,") || machine.hasPrefix("iPad8,") || machine.hasPrefix("iPad11,") || machine.hasPrefix("iPad12,")
                || machine == "iPad13,1" || machine == "iPad13,2" || machine == "iPad13,3" || machine == "iPad13,18" || machine == "iPad13,19" {
                return .compact
            }
            let memoryGB = Double(memory) / (1024.0 * 1024.0 * 1024.0)
            if memoryGB < 4.5 {
                return .compact
            } else if memoryGB < 6.5 {
                return .standard
            } else if memoryGB < 10.5 {
                return .pro
            } else {
                return .ultra
            }
        }

        // Static fallback based on machine string:
        // iPhone 8/X (A11), iPhone XS/XR (A12), iPhone 11 family (A13): 3-4 GB RAM
        if machine.hasPrefix("iPhone10,") || machine.hasPrefix("iPhone11,") || machine.hasPrefix("iPhone12,") {
            return .compact
        }
        // iPhone 12 family (A14): iPhone13,1–13,4
        if machine.hasPrefix("iPhone13,") { return .compact }
        // iPhone SE 2 (A13, 3 GB): iPhone12,8
        // iPhone 13 mini (iPhone14,4), iPhone 13 (iPhone14,5), iPhone SE 3 (iPhone14,6) (A15, 4 GB): compact
        if machine == "iPhone12,8" || machine == "iPhone14,4" || machine == "iPhone14,5" || machine == "iPhone14,6" {
            return .compact
        }

        // Standard iPads and pre-A15 iPad Pros: 3–4 GB RAM
        // iPad 5th gen (iPad6,11, iPad6,12)
        // iPad 6th/7th gen (iPad7,5, iPad7,6, iPad7,11, iPad7,12)
        // iPad Pro 11" 1st gen / 12.9" 3rd gen (A12X/A12Z, iPad8,1–iPad8,8)
        // iPad mini 5 (iPad11,1, iPad11,2), iPad Air 3 (iPad11,3, iPad11,4), iPad 8th gen (iPad11,6, iPad11,7)
        // iPad 9th gen (iPad12,1, iPad12,2)
        // iPad Air 4 (iPad13,1, iPad13,2, iPad13,3), iPad 10th gen (iPad13,18, iPad13,19)
        // iPad mini 6 (iPad14,1, iPad14,2)
        if machine.hasPrefix("iPad6,") || machine.hasPrefix("iPad7,") || machine.hasPrefix("iPad8,") || machine.hasPrefix("iPad11,") || machine.hasPrefix("iPad12,") {
            return .compact
        }
        if machine == "iPad13,1" || machine == "iPad13,2" || machine == "iPad13,3" || machine == "iPad13,18" || machine == "iPad13,19" {
            return .compact
        }
        if machine == "iPad14,1" || machine == "iPad14,2" {
            return .compact
        }

        // iPhone 13 Pro / 13 Pro Max (iPhone14,2, iPhone14,3) (6 GB)
        // iPhone 14 / 14 Plus (iPhone14,7, iPhone14,8) (6 GB)
        // iPhone 14 Pro / 14 Pro Max / 15 / 15 Plus (iPhone15,x) (6 GB)
        if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone15,") { return .standard }
        // iPhone 15 Pro / 15 Pro Max → iPhone16,1 / 16,2 (8 GB)
        if machine.hasPrefix("iPhone16,") { return .pro }
        // iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max → iPhone17,1–17,4 (8 GB)
        if machine.hasPrefix("iPhone17,") { return .pro }
        // iPhone 17 Pro Max: iPhone18,4 (12 GB) -> .ultra
        if machine == "iPhone18,4" { return .ultra }
        // iPhone 17 family (non-Max): iPhone18,1–18,3 (8 GB) -> .pro
        if machine.hasPrefix("iPhone18,") { return .pro }
        // Simulator, M-series iPad, unknown future — default to .pro so we do not hide everything.
        // The download guard still blocks oversize loads.
        return .pro
    }
}
