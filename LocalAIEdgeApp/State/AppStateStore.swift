import Foundation
import Observation

@MainActor
@Observable
final class AppStateStore {
    private(set) var catalog: [ModelCatalogItem]
    private(set) var installedModels: [InstalledModel]
    private(set) var chatSessions: [ChatSession]
    var selectedSessionID: UUID? {
        didSet { saveSelectedSessionID() }
    }
    var settings: AppSettings

    private static let installedModelsKey = "persistedInstalledModels"
    private static let settingsKey = "persistedAppSettings"
    private static let chatSessionsKey = "persistedChatSessions"
    private static let selectedSessionIDKey = "persistedSelectedSessionID"
    private static let placeholderSessionTitle = "New Chat"
    private static let maxPersistedImageBytes = 600_000

    init(
        catalog: [ModelCatalogItem] = MockCatalogData.items,
        installedModels: [InstalledModel] = MockCatalogData.installedModels,
        chatSessions: [ChatSession] = MockCatalogData.sessions,
        settings: AppSettings = .default
    ) {
        self.catalog = catalog
        if let savedSessions = Self.loadChatSessions(), !savedSessions.isEmpty {
            self.chatSessions = savedSessions
                .map(Self.sanitizedSessionForPersistence)
                .map(Self.normalizedSessionTitle)
        } else {
            self.chatSessions = chatSessions.map(Self.normalizedSessionTitle)
        }
        self.selectedSessionID = Self.loadSelectedSessionID()

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

        migrateUnsupportedCatalogEntriesIfNeeded()
    }

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return chatSessions.first }
        return chatSessions.first(where: { $0.id == selectedSessionID }) ?? chatSessions.first
    }

    var defaultModel: InstalledModel? {
        if let defaultModelID = settings.defaultModelID {
            return installedModels.first(where: {
                $0.catalogItem.id == defaultModelID &&
                isReadyChatModel($0)
            })
        }

        return installedModels.first(where: { $0.isDefault && isReadyChatModel($0) })
            ?? installedModels.first(where: isReadyChatModel)
    }

    var availableChatModels: [InstalledModel] {
        installedModels.filter(isReadyChatModel)
    }

    func setDefaultModel(id: UUID) {
        guard installedModels.contains(where: { $0.catalogItem.id == id && isReadyChatModel($0) }) else {
            return
        }

        settings.defaultModelID = id
        installedModels = installedModels.map { model in
            var updated = model
            updated.isDefault = isReadyChatModel(model) && model.catalogItem.id == id
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
        if item.primaryUse == .chat && settings.defaultModelID == nil {
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
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        chatSessions[sessionIndex].messages.append(message)
        chatSessions[sessionIndex].updatedAt = .now
        chatSessions[sessionIndex] = Self.normalizedSessionTitle(chatSessions[sessionIndex])
        saveChatSessions()
    }

    func updateMessageText(_ messageID: UUID, in sessionID: UUID, text: String, persist: Bool = true) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        guard let messageIndex = chatSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        chatSessions[sessionIndex].messages[messageIndex].text = text
        chatSessions[sessionIndex].updatedAt = .now
        if persist {
            saveChatSessions()
        }
    }

    func updateMessageThinking(
        _ messageID: UUID,
        in sessionID: UUID,
        thinkingContent: String?,
        thinkingDurationSeconds: Int? = nil,
        persist: Bool = false
    ) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard let messageIndex = chatSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        chatSessions[sessionIndex].messages[messageIndex].thinkingContent = thinkingContent
        chatSessions[sessionIndex].messages[messageIndex].thinkingDurationSeconds = thinkingDurationSeconds
        chatSessions[sessionIndex].updatedAt = .now
        if persist { saveChatSessions() }
    }

    func createSession(using modelID: UUID?) {
        let session = ChatSession(
            title: Self.placeholderSessionTitle,
            modelID: modelID,
            messages: []
        )
        chatSessions.insert(session, at: 0)
        selectedSessionID = session.id
        saveChatSessions()
    }

    func renameSession(_ sessionID: UUID, title: String) {
        chatSessions = chatSessions.map { session in
            guard session.id == sessionID else { return session }
            var updated = session
            updated.title = title
            return updated
        }
        saveChatSessions()
    }

    func deleteSession(_ sessionID: UUID) {
        chatSessions.removeAll(where: { $0.id == sessionID })
        selectedSessionID = chatSessions.first?.id
        saveChatSessions()
    }

    func reconcileInstalledFiles() {
        for item in catalog where item.runtimeType == .gguf {
            guard let localPath = URLModelDownloadService.installedLocalPath(for: item) else { continue }
            markInstallCompleted(for: item, localPath: localPath)
        }
    }

    func persistSettings() {
        saveSettings()
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

    private func saveChatSessions() {
        let sanitized = chatSessions.map(Self.sanitizedSessionForPersistence)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSessionsKey)
    }

    private static func loadChatSessions() -> [ChatSession]? {
        guard let data = UserDefaults.standard.data(forKey: chatSessionsKey) else { return nil }
        return try? JSONDecoder().decode([ChatSession].self, from: data)
    }

    private static func sanitizedSessionForPersistence(_ session: ChatSession) -> ChatSession {
        var sanitized = session
        sanitized.messages = session.messages.map(Self.sanitizedMessageForPersistence)
        return sanitized
    }

    private static func sanitizedMessageForPersistence(_ message: ChatMessage) -> ChatMessage {
        guard let imageData = message.imageData, imageData.count > maxPersistedImageBytes else {
            return message
        }

        return ChatMessage(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            citations: message.citations,
            imageData: nil,
            thinkingContent: message.thinkingContent,
            thinkingDurationSeconds: message.thinkingDurationSeconds
        )
    }

    private func saveSelectedSessionID() {
        UserDefaults.standard.set(selectedSessionID?.uuidString, forKey: Self.selectedSessionIDKey)
    }

    private static func loadSelectedSessionID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: selectedSessionIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    private static func normalizedSessionTitle(_ session: ChatSession) -> ChatSession {
        guard shouldAutoRename(session.title), let generatedTitle = generatedTitle(from: session.messages) else {
            return session
        }

        var updated = session
        updated.title = generatedTitle
        return updated
    }

    private static func shouldAutoRename(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare(placeholderSessionTitle) == .orderedSame
    }

    private static func generatedTitle(from messages: [ChatMessage]) -> String? {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else { return nil }

        let cleanedText = firstUserMessage.text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanedText.isEmpty {
            let preview = String(cleanedText.prefix(48))
            return cleanedText.count > 48 ? preview + "..." : preview
        }

        if firstUserMessage.imageData != nil {
            return "Image chat"
        }

        return nil
    }

    private func isReadyChatModel(_ model: InstalledModel) -> Bool {
        guard model.catalogItem.primaryUse == .chat,
              model.installState == .installed else {
            return false
        }

        switch model.catalogItem.runtimeType {
        case .gguf:
            return model.fileURL != nil
        case .mlx:
#if targetEnvironment(simulator)
            return false
#else
            return true
#endif
        }
    }

    /// One-time migration for catalog entries that are no longer supported by the shipped runtimes.
    private func migrateUnsupportedCatalogEntriesIfNeeded() {
        let deprecatedModelIDs: Set<String> = [
            "mlx-community/gemma-4-e2b-it-4bit",
            "mlx-community/gemma-4-e4b-it-4bit",
            "mlx-community/gemma-3n-E2B-it-4bit",
            "mlx-community/gemma-3n-E4B-it-4bit",
            "mlx-community/gemma-3n-E2B-it-lm-4bit",
            "mlx-community/gemma-3n-E4B-it-lm-4bit",
            "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            "mlx-community/Qwen3.5-2B-MLX-4bit",
            "mlx-community/Qwen3.5-4B-MLX-4bit",
            "mlx-community/Qwen3.5-9B-MLX-4bit",
            "mlx-community/LFM2.5-VL-1.6B-4bit"
        ]

        var didChange = false
        var migratedDefaultModelID = settings.defaultModelID

        let migrated = installedModels.compactMap { model -> InstalledModel? in
            guard let oldModelID = model.catalogItem.mlxModelID,
                                    deprecatedModelIDs.contains(oldModelID) else {
                return model
            }

            didChange = true
            if migratedDefaultModelID == model.catalogItem.id {
                migratedDefaultModelID = nil
            }
            return nil
        }

        if didChange {
            installedModels = migrated
            settings.defaultModelID = migratedDefaultModelID
            saveInstalledModels()
            saveSettings()
        }
    }
}
