import Foundation
import OSLog

private let shareLogger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "ShareInbox")

/// Reads and drains the App Group share inbox. Each item is a folder holding
/// `payload.json` plus an optional copied file. Items older than 24 hours are
/// discarded rather than imported.
struct ShareInbox {
    /// File names the extension may write for the copied item.
    static let payloadFileName = "payload.json"
    static let staleItemAge: TimeInterval = 24 * 60 * 60

    let inboxURL: URL?
    private let fileManager: FileManager

    init(inboxURL: URL? = AppGroup.inboxURL, fileManager: FileManager = .default) {
        self.inboxURL = inboxURL
        self.fileManager = fileManager
    }

    // MARK: - Writing (Share Extension side)

    /// Writes a payload (and optional file) into the inbox and returns its id.
    @discardableResult
    func enqueue(_ payload: SharePayload, fileContents: Data? = nil) throws -> UUID {
        guard let inboxURL else { throw ShareInboxError.containerUnavailable }
        let itemURL = inboxURL.appendingPathComponent(payload.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)

        if let fileContents, let fileName = payload.fileName {
            try fileContents.write(to: itemURL.appendingPathComponent(fileName), options: .atomic)
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: itemURL.appendingPathComponent(Self.payloadFileName), options: .atomic)
        return payload.id
    }

    // MARK: - Reading (app side)

    /// Every pending item, oldest first, with stale items removed first.
    func pending(now: Date = .now) -> [SharePayload] {
        purgeStale(now: now)
        guard let inboxURL,
              let itemURLs = try? fileManager.contentsOfDirectory(
                  at: inboxURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return itemURLs
            .compactMap { payload(at: $0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Reads a single payload by id (used by the `share/<id>` deep link).
    func payload(id: UUID) -> SharePayload? {
        guard let inboxURL else { return nil }
        return payload(at: inboxURL.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    /// URL of the copied file for a payload, when one exists.
    func fileURL(for payload: SharePayload) -> URL? {
        guard let inboxURL, let fileName = payload.fileName else { return nil }
        let url = inboxURL
            .appendingPathComponent(payload.id.uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Atomically takes ownership of an item by deleting its `payload.json` marker.
    ///
    /// Both `pending()` and `payload(id:)` require that marker, so once one caller has
    /// claimed an item a second reader finds nothing. This matters because the inbox is
    /// drained from BOTH `onAppear` and `didBecomeActive` while the extension also opens
    /// an `edgemindai://share/<id>` deep link; the file import suspends on the
    /// `DocumentIndexer` actor, and inside that window the same file was imported twice.
    /// Safe because callers are `@MainActor`, so the check-and-delete cannot interleave.
    /// Returns false when the item was already claimed or is gone.
    @discardableResult
    func claim(id: UUID) -> Bool {
        guard let inboxURL else { return false }
        let marker = inboxURL
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent(Self.payloadFileName)
        guard fileManager.fileExists(atPath: marker.path) else { return false }
        do {
            try fileManager.removeItem(at: marker)
            return true
        } catch {
            return false
        }
    }

    /// Removes an item after it has been imported.
    func remove(id: UUID) {
        guard let inboxURL else { return }
        try? fileManager.removeItem(at: inboxURL.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    /// Removes every item older than `staleItemAge`.
    func purgeStale(now: Date = .now) {
        guard let inboxURL,
              let itemURLs = try? fileManager.contentsOfDirectory(
                  at: inboxURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for itemURL in itemURLs {
            guard let payload = payload(at: itemURL) else {
                try? fileManager.removeItem(at: itemURL)
                continue
            }
            if now.timeIntervalSince(payload.createdAt) > Self.staleItemAge {
                shareLogger.log("Discarding stale share item \(payload.id.uuidString, privacy: .public)")
                try? fileManager.removeItem(at: itemURL)
            }
        }
    }

    // MARK: - Private

    private func payload(at itemURL: URL) -> SharePayload? {
        let url = itemURL.appendingPathComponent(Self.payloadFileName)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(SharePayload.self, from: data) else {
            return nil
        }
        return payload
    }
}

enum ShareInboxError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "The shared container is unavailable. Check the App Group entitlement."
        }
    }
}
