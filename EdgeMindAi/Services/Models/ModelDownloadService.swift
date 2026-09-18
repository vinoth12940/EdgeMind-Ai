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
    case insufficientDiskSpace(required: Double, available: Double)

    var errorDescription: String? {
        switch self {
        case .exceedsDeviceBudget(let required, let available):
            return "This model needs about \(String(format: "%.1f", required)) GB. This device budget is about \(String(format: "%.1f", available)) GB."
        case .insufficientDiskSpace(let required, let available):
            return "Not enough free storage: this download needs about \(String(format: "%.1f", required)) GB and only \(String(format: "%.1f", available)) GB is free. Free up space and try again."
        }
    }
}

enum ModelDownloadConsentStore {
    private static let key = "mlx.downloadConsent"

    static func hasConsent(for item: ModelCatalogItem) -> Bool {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: key) else {
            return false
        }
        return dictionary[item.id.uuidString] != nil
    }

    static func recordConsent(for item: ModelCatalogItem) {
        var dictionary = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        dictionary[item.id.uuidString] = Date()
        UserDefaults.standard.set(dictionary, forKey: key)
    }

    static func resetConsent(for item: ModelCatalogItem) {
        guard var dictionary = UserDefaults.standard.dictionary(forKey: key) else { return }
        dictionary.removeValue(forKey: item.id.uuidString)
        UserDefaults.standard.set(dictionary, forKey: key)
    }
}

enum ModelInstallGuard {
    static func unsupportedTierMessage(for item: ModelCatalogItem, currentTier: DeviceTier = .current()) -> String? {
        guard item.minimumTier > currentTier else { return nil }
        return "Needs \(item.minimumTier.displayName)"
    }

    static func memoryConsentRequirement(
        for item: ModelCatalogItem,
        currentTier: DeviceTier = .current()
    ) -> (required: Double, available: Double)? {
        let required = item.estimatedResidentGB(contextTokens: currentTier.safeContextTokens)
        guard required > currentTier.usableWeightGB else { return nil }
        guard !ModelDownloadConsentStore.hasConsent(for: item) else { return nil }
        return (required, currentTier.usableWeightGB)
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
        // NO `hub` component here. The app builds its hub client with
        // `HubCache(cacheDirectory: <Caches>/huggingface)`, and in swift-huggingface
        // `HubCache.repoDirectory` is just `<cacheDirectory>/models--org--repo`. The
        // `hub` segment only exists for `CacheLocationProvider.defaultCacheDirectory()`,
        // which this app does not use — so including it made `isDownloaded` ALWAYS
        // false: every MLX model looked uninstalled (and deleting one freed nothing).
        return base
            .appending(path: "huggingface", directoryHint: .isDirectory)
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

    private let stateQueue = DispatchQueue(label: "EdgeMindAi.ModelDownloadService")
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
            let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            if fileSize > 1_000_000 {
                let installed = makeInstalledModel(for: model, destinationURL: destinationURL)
                onEvent(.init(modelID: model.id, state: .installed, progress: 1, localPath: destinationURL.path, message: nil))
                return installed
            } else {
                try? FileManager.default.removeItem(at: destinationURL)
            }
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

        var mutableDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableDirectory.setResourceValues(resourceValues)

        return mutableDirectory
    }

    private func guardBudget(for item: ModelCatalogItem) throws {
        let tier = DeviceTier.current()
        let required = item.estimatedResidentGB(contextTokens: tier.safeContextTokens)
        guard required <= tier.usableWeightGB || ModelDownloadConsentStore.hasConsent(for: item) else {
            throw ModelDownloadError.exceedsDeviceBudget(required: required, available: tier.usableWeightGB)
        }

        // Free storage, not just RAM. Without this a 0.15-3.7 GB download started on a
        // nearly-full device, ran for minutes consuming the remaining space, then failed
        // with a generic "the file couldn't be saved". The audit path already refuses to
        // start in this situation — the user-facing install path did not.
        let freeGB = ModelAuditRunner.freeDiskGB()
        let neededGB = item.parsedDiskSizeGBForEstimator + 0.5
        // A 0 reading means the volume could not be queried; don't block the download.
        guard freeGB <= 0 || freeGB >= neededGB else {
            throw ModelDownloadError.insufficientDiskSpace(required: neededGB, available: freeGB)
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

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: location)
            let errorMessage = "Download failed: HTTP \(httpResponse.statusCode) (\(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)))"
            let error = NSError(domain: "ModelDownload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            pendingDownload.onEvent(.init(modelID: pendingDownload.model.id, state: .failed, progress: 0, localPath: nil, message: errorMessage))
            pendingDownload.continuation.resume(throwing: error)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: pendingDownload.destinationURL.path) {
                try? FileManager.default.removeItem(at: pendingDownload.destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: pendingDownload.destinationURL)

            completeAsInstalled(pendingDownload)
        } catch {
            try? FileManager.default.removeItem(at: location)
            pendingDownload.onEvent(.init(modelID: pendingDownload.model.id, state: .failed, progress: 0, localPath: nil, message: error.localizedDescription))
            pendingDownload.continuation.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        if let originalHost = task.originalRequest?.url?.host?.lowercased(),
           let newHost = request.url?.host?.lowercased(),
           originalHost != newHost {
            redirectedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirectedRequest)
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
