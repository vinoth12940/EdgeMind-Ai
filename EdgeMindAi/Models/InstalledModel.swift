import Foundation

struct InstalledModel: Identifiable, Hashable, Codable {
    enum InstallState: String, Codable, Hashable {
        case notInstalled
        case downloading
        case installed
        case failed
    }

    let id: UUID
    let catalogItem: ModelCatalogItem
    var installState: InstallState
    var progress: Double
    var installedAt: Date?
    var localPath: String?
    var isDefault: Bool
    var statusMessage: String?

    init(
        id: UUID = UUID(),
        catalogItem: ModelCatalogItem,
        installState: InstallState,
        progress: Double = 0,
        installedAt: Date? = nil,
        localPath: String? = nil,
        isDefault: Bool = false,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.catalogItem = catalogItem
        self.installState = installState
        self.progress = progress
        self.installedAt = installedAt
        self.localPath = localPath
        self.isDefault = isDefault
        self.statusMessage = statusMessage
    }

    var fileURL: URL? {
        guard let localPath else { return nil }
        return URL(fileURLWithPath: localPath)
    }
}
