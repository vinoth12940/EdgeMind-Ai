// LocalAIEdgeApp/Services/Inference/RuntimeProfileStore.swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "RuntimeProfileStore")

/// Loads bundled RuntimeProfiles.json once, exposes profile lookup.
/// In Debug builds, a local Documents override can shadow bundled entries.
/// In Release builds, the override path is compiled out — no override can ship.
final class RuntimeProfileStore {
    private let profiles: [UUID: RuntimeProfile]

    init(bundleLoader: (() -> [RuntimeProfile])? = nil, overrideLoader: (() -> [RuntimeProfile])? = nil) {
        let bundled = (bundleLoader ?? Self.loadBundled)()
        let overridden = (overrideLoader ?? Self.loadOverride)()
        var merged = Dictionary(uniqueKeysWithValues: bundled.map { ($0.catalogID, $0) })
        for o in overridden {
            merged[o.catalogID] = o  // override shadows bundled
            logger.log("RuntimeProfile override active for \(o.catalogID.uuidString, privacy: .public)")
        }
        self.profiles = merged
    }

    func profile(for catalogID: UUID) -> RuntimeProfile? {
        profiles[catalogID]
    }

    private static func loadBundled() -> [RuntimeProfile] {
        guard let url = Bundle.main.url(forResource: "RuntimeProfiles", withExtension: "json") else {
            logger.error("RuntimeProfiles.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RuntimeProfile].self, from: data)
        } catch {
            logger.error("Failed to decode RuntimeProfiles.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    #if DEBUG
    private static func loadOverride() -> [RuntimeProfile] {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        let url = dir.appending(path: "RuntimeProfiles.override.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RuntimeProfile].self, from: data)) ?? []
    }
    #else
    private static func loadOverride() -> [RuntimeProfile] { [] }
    #endif
}
