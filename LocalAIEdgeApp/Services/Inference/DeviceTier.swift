import Foundation

/// Classifies the device into a coarse RAM / compute bucket so the catalog
/// and download guard can hide or warn about models that will not run safely.
///
/// Tier boundaries come from iOS jetsam behavior: foreground apps are killed
/// around ~55–60% of physical RAM. `usableWeightGB` targets ~35% of total,
/// leaving room for KV cache, MLX GPU cache, vision tower, app heap, OS.
enum DeviceTier: String, Comparable, Codable, CaseIterable {
    case compact   // 4 GB devices: iPhone 12 family, SE 2/3, 13 mini
    case standard  // 6 GB devices: iPhone 13, 14, 15 non-Pro
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

    /// Read-only classifier — pulls `hw.machine` via `DeviceCapabilityService.machineModel()`.
    static func current() -> DeviceTier {
        classify(machine: DeviceCapabilityService.machineModel())
    }

    /// Testable — inject a known machine string.
    static func classify(machine: String) -> DeviceTier {
        // iPhone 12 family (A14): iPhone13,1–13,4
        if machine.hasPrefix("iPhone13,") { return .compact }
        // iPhone SE 3 (A15, 4 GB): iPhone14,6  |  iPhone SE 2 (A13, 3 GB): iPhone12,8 — compact, MLX is marginal.
        if machine == "iPhone12,8" || machine == "iPhone14,6" { return .compact }
        // iPhone 13 mini (iPhone14,4) ships 4 GB — treat as compact for safety (A15 but RAM-constrained).
        if machine == "iPhone14,4" { return .compact }
        // iPhone 13 / 13 Pro / 13 Pro Max / 14 / 14 Plus / 14 Pro / 14 Pro Max (6 GB)
        // iPhone 15 / 15 Plus (6 GB) → identifiers iPhone15,4 / 15,5
        if machine.hasPrefix("iPhone14,") || machine == "iPhone15,4" || machine == "iPhone15,5" { return .standard }
        // iPhone 15 Pro / 15 Pro Max → iPhone16,1 / 16,2 (8 GB)
        if machine.hasPrefix("iPhone16,") { return .pro }
        // iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max → iPhone17,1–17,4 (8 GB)
        if machine.hasPrefix("iPhone17,") { return .pro }
        // Simulator, iPad, unknown future — default to .pro so we do not hide everything.
        // The download guard still blocks oversize loads.
        return .pro
    }
}
