import Foundation

struct ModelDownloadEvent: Sendable {
    let modelID: UUID
    let state: InstalledModel.InstallState
    let progress: Double
    let localPath: String?
    let message: String?
}

protocol ModelDownloadService {
    func beginInstall(
        for model: ModelCatalogItem,
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> InstalledModel

    func removeInstall(for model: InstalledModel) async throws
}

enum ModelDownloadError: LocalizedError {
    case exceedsDeviceBudget(required: Double, available: Double)

    var errorDescription: String? {
        switch self {
        case .exceedsDeviceBudget(let required, let available):
            return "This model needs about \(String(format: "%.1f", required)) GB. This device budget is about \(String(format: "%.1f", available)) GB."
        }
    }
}

enum ModelDownloadConsentStore {
    private static let key = "mlx.downloadConsent"

    static func hasConsent(for item: ModelCatalogItem) -> Bool {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] else {
            return false
        }
        return dictionary[item.id.uuidString] != nil
    }

    static func recordConsent(for item: ModelCatalogItem) {
        var dictionary = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        dictionary[item.id.uuidString] = Date()
        UserDefaults.standard.set(dictionary, forKey: key)
    }
}

enum ModelDownloadServiceError: LocalizedError {
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL:
            return "This model is missing a direct GGUF download URL."
        }
    }
}

enum MLXModelCache {
    static func cacheDirectory(for modelID: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directoryName = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        return base
            .appending(path: "huggingface", directoryHint: .isDirectory)
            .appending(path: "hub", directoryHint: .isDirectory)
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    static func isDownloaded(_ modelID: String) -> Bool {
        guard let cacheDirectory = cacheDirectory(for: modelID) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cacheDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let snapshotsDirectory = cacheDirectory.appending(path: "snapshots", directoryHint: .isDirectory)
        var snapshotsIsDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: snapshotsDirectory.path, isDirectory: &snapshotsIsDirectory)
            && snapshotsIsDirectory.boolValue
    }
}

final class URLModelDownloadService: NSObject, ModelDownloadService {
    private struct PendingDownload {
        let model: ModelCatalogItem
        let destinationURL: URL
        let onEvent: @Sendable (ModelDownloadEvent) -> Void
        let continuation: CheckedContinuation<InstalledModel, Error>
    }

    private let stateQueue = DispatchQueue(label: "LocalAIEdgeApp.ModelDownloadService")
    private var pendingDownloads: [Int: PendingDownload] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    static func destinationURL(for model: ModelCatalogItem) throws -> URL {
        try modelsDirectory().appending(path: model.downloadFileName ?? "\(model.id.uuidString).gguf")
    }

    static func installedLocalPath(for model: ModelCatalogItem) -> String? {
        guard let url = try? destinationURL(for: model), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url.path
    }

    private func makeInstalledModel(for model: ModelCatalogItem, destinationURL: URL) -> InstalledModel {
        InstalledModel(
            catalogItem: model,
            installState: .installed,
            progress: 1,
            installedAt: .now,
            localPath: destinationURL.path
        )
    }

    private func completeAsInstalled(_ pendingDownload: PendingDownload) {
        pendingDownload.onEvent(.init(
            modelID: pendingDownload.model.id,
            state: .installed,
            progress: 1,
            localPath: pendingDownload.destinationURL.path,
            message: nil
        ))
        pendingDownload.continuation.resume(returning: makeInstalledModel(for: pendingDownload.model, destinationURL: pendingDownload.destinationURL))
    }

    func beginInstall(
        for model: ModelCatalogItem,
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> InstalledModel {
        try guardBudget(for: model)

        guard let downloadURL = model.downloadURL else {
            throw ModelDownloadServiceError.missingDownloadURL
        }

        let destinationURL = try Self.destinationURL(for: model)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let installed = makeInstalledModel(for: model, destinationURL: destinationURL)
            onEvent(.init(modelID: model.id, state: .installed, progress: 1, localPath: destinationURL.path, message: nil))
            return installed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = HFTokenManager.authorizedRequest(for: downloadURL)
            let task = session.downloadTask(with: request)
            stateQueue.sync {
                pendingDownloads[task.taskIdentifier] = PendingDownload(
                    model: model,
                    destinationURL: destinationURL,
                    onEvent: onEvent,
                    continuation: continuation
                )
            }
            onEvent(.init(modelID: model.id, state: .downloading, progress: 0, localPath: nil, message: "Preparing download"))
            task.resume()
        }
    }

    func removeInstall(for model: InstalledModel) async throws {
        guard let fileURL = model.fileURL else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func pendingDownload(for taskID: Int) -> PendingDownload? {
        stateQueue.sync { pendingDownloads[taskID] }
    }

    private func takePendingDownload(for taskID: Int) -> PendingDownload? {
        stateQueue.sync { pendingDownloads.removeValue(forKey: taskID) }
    }

    private static func modelsDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Models", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func guardBudget(for item: ModelCatalogItem) throws {
        let tier = DeviceTier.current()
        let required = item.estimatedResidentGB(contextTokens: tier.safeContextTokens)
        guard required <= tier.usableWeightGB || ModelDownloadConsentStore.hasConsent(for: item) else {
            throw ModelDownloadError.exceedsDeviceBudget(required: required, available: tier.usableWeightGB)
        }
    }
}

extension URLModelDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let pendingDownload = pendingDownload(for: downloadTask.taskIdentifier) else { return }
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        } else {
            progress = downloadTask.progress.fractionCompleted
        }

        pendingDownload.onEvent(.init(modelID: pendingDownload.model.id, state: .downloading, progress: progress, localPath: nil, message: nil))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let pendingDownload = takePendingDownload(for: downloadTask.taskIdentifier) else { return }

        do {
            if FileManager.default.fileExists(atPath: pendingDownload.destinationURL.path) {
                try? FileManager.default.removeItem(at: location)
                completeAsInstalled(pendingDownload)
                return
            }

            try FileManager.default.moveItem(at: location, to: pendingDownload.destinationURL)

            completeAsInstalled(pendingDownload)
        } catch {
            if FileManager.default.fileExists(atPath: pendingDownload.destinationURL.path) {
                try? FileManager.default.removeItem(at: location)
                completeAsInstalled(pendingDownload)
                return
            }

            pendingDownload.onEvent(.init(modelID: pendingDownload.model.id, state: .failed, progress: 0, localPath: nil, message: error.localizedDescription))
            pendingDownload.continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let pendingDownload = takePendingDownload(for: task.taskIdentifier) else { return }
        pendingDownload.onEvent(.init(modelID: pendingDownload.model.id, state: .failed, progress: 0, localPath: nil, message: error.localizedDescription))
        pendingDownload.continuation.resume(throwing: error)
    }
}

struct MockModelDownloadService: ModelDownloadService {
    func beginInstall(
        for model: ModelCatalogItem,
        onEvent: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> InstalledModel {
        try await Task.sleep(for: .milliseconds(250))
        let localPath = "/Models/\(model.displayName).bin"
        onEvent(.init(modelID: model.id, state: .installed, progress: 1, localPath: localPath, message: nil))
        return InstalledModel(
            catalogItem: model,
            installState: .installed,
            progress: 1,
            installedAt: .now,
            localPath: localPath
        )
    }

    func removeInstall(for model: InstalledModel) async throws {
        try await Task.sleep(for: .milliseconds(120))
    }
}
