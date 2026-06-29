import Foundation

protocol AuditDownloader {
    @MainActor func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel?
    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel
    func remove(_ model: InstalledModel, store: AppStateStore) async throws
}

struct DefaultAuditDownloader: AuditDownloader {
    let ggufService: ModelDownloadService

    init(ggufService: ModelDownloadService = URLModelDownloadService()) {
        self.ggufService = ggufService
    }

    @MainActor
    func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel? {
        store.installedModels.first { model in
            guard model.catalogItem.id == item.id else { return false }
            switch item.runtimeType {
            case .gguf, .liteRTLM:
                guard let fileURL = model.fileURL else { return false }
                return FileManager.default.fileExists(atPath: fileURL.path)
            case .mlx:
                return model.localPath == item.mlxModelID
            case .foundationModels:
                return model.localPath == AppleFoundationModelService.localPathMarker
            }
        }
    }

    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel {
        if let existing = await installedModel(for: item, store: store) {
            return existing
        }

        switch item.runtimeType {
        case .gguf, .liteRTLM:
            return try await ggufService.beginInstall(for: item) { event in
                progress(event.progress)
            }
        case .mlx:
            guard let mlxModelID = item.mlxModelID else {
                throw ModelDownloadServiceError.missingDownloadURL
            }
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            try await MLXRuntime.shared.preloadModel(mlxModelID, isVision: item.supportsVision) { downloadProgress in
                progress(downloadProgress.fraction)
            }
            #else
            progress(1.0)
            #endif
            return InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1,
                installedAt: .now,
                localPath: mlxModelID
            )
        case .foundationModels:
            progress(1.0)
            return InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1,
                installedAt: .now,
                localPath: AppleFoundationModelService.localPathMarker
            )
        }
    }

    func remove(_ model: InstalledModel, store: AppStateStore) async throws {
        switch model.catalogItem.runtimeType {
        case .gguf, .liteRTLM:
            try await ggufService.removeInstall(for: model)
        case .mlx:
            guard let mlxModelID = model.catalogItem.mlxModelID else { return }
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            await MLXRuntime.shared.removeModelCache(for: mlxModelID)
            #else
            if let cacheDirectory = MLXModelCache.cacheDirectory(for: mlxModelID) {
                try? FileManager.default.removeItem(at: cacheDirectory)
            }
            #endif
        case .foundationModels:
            return
        }
    }
}

#if DEBUG
struct MockAuditDownloader: AuditDownloader {
    var installed: [UUID: InstalledModel] = [:]
    var preloadResult: (ModelCatalogItem) -> Result<InstalledModel, Error> = { item in
        .success(
            InstalledModel(
                catalogItem: item,
                installState: .installed,
                progress: 1,
                installedAt: .now,
                localPath: item.mlxModelID
            )
        )
    }
    var removeAction: (InstalledModel) async throws -> Void = { _ in }

    @MainActor
    func installedModel(for item: ModelCatalogItem, store: AppStateStore) -> InstalledModel? {
        installed[item.id]
    }

    func preloadIfNeeded(
        item: ModelCatalogItem,
        store: AppStateStore,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> InstalledModel {
        progress(1.0)
        return try preloadResult(item).get()
    }

    func remove(_ model: InstalledModel, store: AppStateStore) async throws {
        try await removeAction(model)
    }
}
#endif
