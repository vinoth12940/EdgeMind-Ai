import Foundation
import Observation

@Observable
final class AppStateStore {
    private(set) var catalog: [ModelCatalogItem]
    private(set) var installedModels: [InstalledModel]
    private(set) var chatSessions: [ChatSession]
    var selectedSessionID: UUID?
    var settings: AppSettings

    private static let installedModelsKey = "persistedInstalledModels"
    private static let settingsKey = "persistedAppSettings"

    init(
        catalog: [ModelCatalogItem] = MockCatalogData.items,
        installedModels: [InstalledModel] = MockCatalogData.installedModels,
        chatSessions: [ChatSession] = MockCatalogData.sessions,
        settings: AppSettings = .default
    ) {
        self.catalog = catalog
        self.chatSessions = chatSessions
        self.selectedSessionID = nil

        // Restore persisted settings
        if let savedSettings = Self.loadSettings() {
            self.settings = savedSettings
        } else {
            self.settings = settings
        }

        // Restore persisted installed models
        if let restored = Self.loadInstalledModels(), !restored.isEmpty {
            self.installedModels = restored
        } else {
            self.installedModels = installedModels
        }
    }

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return chatSessions.first }
        return chatSessions.first(where: { $0.id == selectedSessionID })
    }

    var defaultModel: InstalledModel? {
        if let defaultModelID = settings.defaultModelID {
            return installedModels.first(where: {
                $0.catalogItem.id == defaultModelID && $0.installState == .installed && ($0.catalogItem.runtimeType == .mlx || $0.fileURL != nil)
            })
        }

        return installedModels.first(where: { $0.isDefault && $0.installState == .installed && ($0.catalogItem.runtimeType == .mlx || $0.fileURL != nil) })
    }

    func setDefaultModel(id: UUID) {
        settings.defaultModelID = id
        installedModels = installedModels.map { model in
            var updated = model
            updated.isDefault = model.catalogItem.id == id
            return updated
        }
        saveInstalledModels()
        saveSettings()
    }

    func updateInstallState(for modelID: UUID, state: InstalledModel.InstallState, progress: Double) {
        installedModels = installedModels.map { model in
            guard model.catalogItem.id == modelID else { return model }
            var updated = model
            updated.installState = state
            updated.progress = progress
            if state == .installed {
                updated.installedAt = .now
                updated.statusMessage = nil
            }
            return updated
        }
        saveInstalledModels()
    }

    func upsertInstalledModel(_ model: InstalledModel) {
        if let index = installedModels.firstIndex(where: { $0.catalogItem.id == model.catalogItem.id }) {
            installedModels[index] = model
        } else {
            installedModels.append(model)
        }
        saveInstalledModels()
    }

    func updateInstallProgress(for item: ModelCatalogItem, progress: Double, state: InstalledModel.InstallState = .downloading, statusMessage: String? = nil) {
        var existing = installedModels.first(where: { $0.catalogItem.id == item.id })
            ?? InstalledModel(catalogItem: item, installState: state)

        existing.installState = state
        existing.progress = progress
        existing.statusMessage = statusMessage
        if existing.isDefault && state != .installed {
            existing.isDefault = false
        }

        upsertInstalledModel(existing)
    }

    func markInstallCompleted(for item: ModelCatalogItem, localPath: String) {
        var existing = installedModels.first(where: { $0.catalogItem.id == item.id })
            ?? InstalledModel(catalogItem: item, installState: .installed)

        existing.installState = .installed
        existing.progress = 1
        existing.localPath = localPath
        existing.installedAt = .now
        existing.statusMessage = nil
        if settings.defaultModelID == nil {
            existing.isDefault = true
            settings.defaultModelID = item.id
            saveSettings()
        }

        upsertInstalledModel(existing)
    }

    func markInstallFailed(for item: ModelCatalogItem, message: String) {
        var existing = installedModels.first(where: { $0.catalogItem.id == item.id })
            ?? InstalledModel(catalogItem: item, installState: .failed)

        existing.installState = .failed
        existing.statusMessage = message
        existing.progress = 0
        upsertInstalledModel(existing)
    }

    func removeInstalledModel(_ item: ModelCatalogItem) {
        installedModels.removeAll(where: { $0.catalogItem.id == item.id })
        if settings.defaultModelID == item.id {
            settings.defaultModelID = nil
            saveSettings()
        }
        saveInstalledModels()
    }

    func appendMessage(_ message: ChatMessage, to sessionID: UUID) {
        chatSessions = chatSessions.map { session in
            guard session.id == sessionID else { return session }
            var updated = session
            updated.messages.append(message)
            updated.updatedAt = .now
            return updated
        }
    }

    func updateMessageText(_ messageID: UUID, in sessionID: UUID, text: String) {
        chatSessions = chatSessions.map { session in
            guard session.id == sessionID else { return session }
            var updated = session
            if let idx = updated.messages.firstIndex(where: { $0.id == messageID }) {
                updated.messages[idx].text = text
            }
            return updated
        }
    }

    func createSession(using modelID: UUID?) {
        let session = ChatSession(
            title: "New Chat",
            modelID: modelID,
            messages: []
        )
        chatSessions.insert(session, at: 0)
        selectedSessionID = session.id
    }

    func renameSession(_ sessionID: UUID, title: String) {
        chatSessions = chatSessions.map { session in
            guard session.id == sessionID else { return session }
            var updated = session
            updated.title = title
            return updated
        }
    }

    func deleteSession(_ sessionID: UUID) {
        chatSessions.removeAll(where: { $0.id == sessionID })
        selectedSessionID = chatSessions.first?.id
    }

    func reconcileInstalledFiles() {
        for item in catalog where item.runtimeType == .gguf {
            guard let localPath = URLModelDownloadService.installedLocalPath(for: item) else { continue }
            markInstallCompleted(for: item, localPath: localPath)
        }
    }

    // MARK: - Persistence

    private func saveInstalledModels() {
        let toSave = installedModels.filter { $0.installState == .installed }
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        UserDefaults.standard.set(data, forKey: Self.installedModelsKey)
    }

    private static func loadInstalledModels() -> [InstalledModel]? {
        guard let data = UserDefaults.standard.data(forKey: installedModelsKey),
              let models = try? JSONDecoder().decode([InstalledModel].self, from: data) else {
            return nil
        }
        return models.filter { $0.installState == .installed }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private static func loadSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
