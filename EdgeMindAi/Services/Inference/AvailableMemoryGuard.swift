import Darwin
import Foundation
import OSLog

private let memoryGuardLogger = Logger(subsystem: "com.vinothrajalingam.EdgeMindAi", category: "AvailableMemoryGuard")

/// Monitors live physical memory headroom and protects the app against sudden iOS Jetsam kills.
enum AvailableMemoryGuard {

    /// Returns the live available memory in bytes before the process reaches its Jetsam ceiling.
    static func availableMemoryBytes() -> UInt64 {
        #if targetEnvironment(simulator)
        // Simulator on macOS host: default to 16 GB virtual headroom
        return 16 * 1024 * 1024 * 1024
        #else
        let available = os_proc_available_memory()
        return UInt64(max(0, available))
        #endif
    }

    /// Returns the live available memory in gigabytes.
    static func availableMemoryGB() -> Double {
        Double(availableMemoryBytes()) / (1024.0 * 1024.0 * 1024.0)
    }

    /// Checks whether the device currently has enough real-time memory headroom to safely load and run the model.
    ///
    /// - Parameters:
    ///   - model: The model to be loaded or executed.
    ///   - isVision: Whether an image prompt is being attached.
    /// - Returns: A user-friendly error string if memory is insufficient, or `nil` if safe.
    static func checkMemoryHeadroom(for model: ModelCatalogItem, isVision: Bool = false) -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let freeGB = availableMemoryGB()

        // Critical Jetsam threshold: iOS typically sends low memory warnings around 250 MB
        // and terminates the app under ~150–200 MB of remaining headroom.
        let criticalFloorGB = 0.35
        if freeGB < criticalFloorGB {
            memoryGuardLogger.warning("Critically low memory headroom: free=\(freeGB, privacy: .public) GB")
            return "Device memory is critically low (\(String(format: "%.1f", freeGB * 1024)) MB available). Close background apps to avoid iOS terminating the app."
        }

        // Only enforce extra headroom checks for models running on a device tier below their requirement.
        let tier = DeviceTier.current()
        if tier < model.minimumTier {
            let neededGB = model.parsedDiskSizeGBForEstimator * 1.15 + (isVision ? 0.4 : 0.0) + criticalFloorGB
            if freeGB < neededGB {
                memoryGuardLogger.warning("Low memory headroom for below-tier model: free=\(freeGB, privacy: .public) GB, needed=\(neededGB, privacy: .public) GB for \(model.displayName, privacy: .public)")
                return "Device memory is currently low (\(String(format: "%.1f", freeGB)) GB available, ~\(String(format: "%.1f", neededGB)) GB needed). Close background apps or pick a lighter model."
            }
        }

        return nil
        #endif
    }
}
