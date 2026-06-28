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
    var isSidebarOpen = false

    private static let installedModelsKey = "persistedInstalledModels"
    private static let settingsKey = "persistedAppSettings"
    private static let chatSessionsKey = "persistedChatSessions"
    private static let selectedSessionIDKey = "persistedSelectedSessionID"
    private static let placeholderSessionTitle = "New Chat"
    private static let maxPersistedImageBytes = 600_000
    private static let maxPersistedSessions = 40
    private static let maxInMemoryMessagesPerSession = 260
    private static let maxInMemoryMessageTextCharacters = 96_000
    private static let maxInMemoryThinkingCharacters = 64_000
    private static let maxPersistedMessagesPerSession = 180
    private static let maxPersistedMessageTextCharacters = 64_000
    private static let maxPersistedThinkingCharacters = 48_000

    init(
        catalog: [ModelCatalogItem] = MockCatalogData.items,
        installedModels: [InstalledModel] = MockCatalogData.installedModels,
        chatSessions: [ChatSession] = MockCatalogData.sessions,
        settings: AppSettings = .default
    ) {
        self.catalog = catalog
        if let savedSessions = Self.loadChatSessions(), !savedSessions.isEmpty {
            self.chatSessions = savedSessions
                .map(Self.sanitizedSessionForInMemory)
                .map(Self.normalizedSessionTitle)
        } else {
            self.chatSessions = chatSessions
                .map(Self.sanitizedSessionForInMemory)
                .map(Self.normalizedSessionTitle)
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

        reconcilePersistedInstalledModelsWithCurrentCatalog()
        migrateUnsupportedCatalogEntriesIfNeeded()
        ensureSystemFoundationModelAvailable()
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

        chatSessions[sessionIndex].messages.append(Self.sanitizedMessageForInMemory(message))
        chatSessions[sessionIndex] = Self.sanitizedSessionForInMemory(chatSessions[sessionIndex])
        chatSessions[sessionIndex].updatedAt = .now
        chatSessions[sessionIndex] = Self.normalizedSessionTitle(chatSessions[sessionIndex])
        saveChatSessions()
    }

    func removeMessage(_ messageID: UUID, from sessionID: UUID) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        chatSessions[sessionIndex].messages.removeAll { $0.id == messageID }
        chatSessions[sessionIndex].updatedAt = .now
        saveChatSessions()
    }

    func updateMessageText(_ messageID: UUID, in sessionID: UUID, text: String, persist: Bool = true) {
        guard let sessionIndex = chatSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        guard let messageIndex = chatSessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        chatSessions[sessionIndex].messages[messageIndex].text = Self.trimInMemoryText(text)
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
        chatSessions[sessionIndex].messages[messageIndex].thinkingContent = thinkingContent.map(Self.trimInMemoryThinking)
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
        for item in catalog where item.runtimeType == .gguf || item.runtimeType == .liteRTLM {
            guard let localPath = URLModelDownloadService.installedLocalPath(for: item) else { continue }
            markInstallCompleted(for: item, localPath: localPath)
        }

        for item in catalog where item.runtimeType == .mlx {
            guard let mlxModelID = item.mlxModelID,
                  MLXModelCache.isDownloaded(mlxModelID) else {
                continue
            }
            markInstallCompleted(for: item, localPath: mlxModelID)
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
        let sanitized = Self.boundedSessionsForPersistence(chatSessions)
            .map(Self.sanitizedSessionForPersistence)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSessionsKey)
    }

    private static func loadChatSessions() -> [ChatSession]? {
        guard let data = UserDefaults.standard.data(forKey: chatSessionsKey) else { return nil }
        guard let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else {
            return nil
        }
        return boundedSessionsForPersistence(sessions).map(sanitizedSessionForPersistence)
    }

    private static func sanitizedSessionForPersistence(_ session: ChatSession) -> ChatSession {
        var sanitized = session
        sanitized.messages = Self.boundedMessagesForLongChat(
            session.messages,
            maxMessages: Self.maxPersistedMessagesPerSession
        ).map(Self.sanitizedMessageForPersistence)
        return sanitized
    }

    private static func sanitizedSessionForInMemory(_ session: ChatSession) -> ChatSession {
        var sanitized = session
        sanitized.messages = Self.boundedMessagesForLongChat(
            session.messages,
            maxMessages: Self.maxInMemoryMessagesPerSession
        ).map(Self.sanitizedMessageForInMemory)
        return sanitized
    }

    private static func boundedSessionsForPersistence(_ sessions: [ChatSession]) -> [ChatSession] {
        sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxPersistedSessions)
            .map { $0 }
    }

    private static func boundedMessagesForLongChat(_ messages: [ChatMessage], maxMessages: Int) -> [ChatMessage] {
        guard messages.count > maxMessages else { return messages }
        guard maxMessages > 1 else { return Array(messages.suffix(maxMessages)) }

        let firstUser = messages.first(where: { $0.role == .user })
        var retained = Array(messages.suffix(maxMessages))
        if let firstUser, !retained.contains(where: { $0.id == firstUser.id }) {
            retained = [firstUser] + retained.suffix(maxMessages - 1)
        }
        return retained
    }

    private static func sanitizedMessageForInMemory(_ message: ChatMessage) -> ChatMessage {
        ChatMessage(
            id: message.id,
            role: message.role,
            text: trimInMemoryText(message.text),
            createdAt: message.createdAt,
            citations: message.citations,
            attachments: message.attachments,
            thinkingContent: message.thinkingContent.map(trimInMemoryThinking),
            thinkingDurationSeconds: message.thinkingDurationSeconds
        )
    }

    private static func trimInMemoryText(_ text: String) -> String {
        InferenceBudget.trimHistoryText(text, maxCharacters: maxInMemoryMessageTextCharacters)
    }

    private static func trimInMemoryThinking(_ text: String) -> String {
        InferenceBudget.trimHistoryText(text, maxCharacters: maxInMemoryThinkingCharacters)
    }

    private static func sanitizedMessageForPersistence(_ message: ChatMessage) -> ChatMessage {
        let sanitizedAttachments = message.attachments.map {
            $0.sanitized(maxRawBytes: maxPersistedImageBytes, maxExtractedCharacters: 20_000)
        }

        return ChatMessage(
            id: message.id,
            role: message.role,
            text: InferenceBudget.trimHistoryText(message.text, maxCharacters: maxPersistedMessageTextCharacters),
            createdAt: message.createdAt,
            citations: message.citations,
            attachments: sanitizedAttachments,
            thinkingContent: message.thinkingContent.map {
                InferenceBudget.trimHistoryText($0, maxCharacters: maxPersistedThinkingCharacters)
            },
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

        if firstUserMessage.attachments.contains(where: { $0.kind != .image }) {
            return "Document chat"
        }

        return nil
    }

    private func isReadyChatModel(_ model: InstalledModel) -> Bool {
        guard model.catalogItem.primaryUse == .chat,
              model.installState == .installed else {
            return false
        }

        switch model.catalogItem.runtimeType {
        case .gguf, .liteRTLM:
            guard let fileURL = model.fileURL else { return false }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            if model.catalogItem.runtimeType == .liteRTLM {
                return fileURL.pathExtension == "litertlm"
            }
            return true
        case .mlx:
#if targetEnvironment(simulator)
            return false
#else
            guard let mlxModelID = model.catalogItem.mlxModelID,
                  model.localPath == mlxModelID else {
                return false
            }
            return true
#endif
        case .foundationModels:
            return model.localPath == AppleFoundationModelService.localPathMarker
        }
    }

    private func reconcilePersistedInstalledModelsWithCurrentCatalog() {
        var didChange = false
        installedModels = installedModels.map { model in
            guard let currentCatalogItem = currentCatalogItem(for: model) else {
                return model
            }
            let reconciledPath = reconciledLocalPath(model: model, currentCatalogItem: currentCatalogItem)
            let reconciledState = reconciledInstallState(
                model: model,
                currentCatalogItem: currentCatalogItem,
                reconciledPath: reconciledPath
            )
            guard currentCatalogItem != model.catalogItem
                    || reconciledPath != model.localPath
                    || reconciledState != model.installState else {
                return model
            }

            didChange = true
            let updated = InstalledModel(
                id: model.id,
                catalogItem: currentCatalogItem,
                installState: reconciledState,
                progress: reconciledState == .installed ? model.progress : 0,
                installedAt: reconciledState == .installed ? model.installedAt : nil,
                localPath: reconciledPath,
                isDefault: model.isDefault,
                statusMessage: model.statusMessage
            )

            if settings.defaultModelID == model.catalogItem.id {
                settings.defaultModelID = currentCatalogItem.id
            }

            return updated
        }

        if didChange {
            saveInstalledModels()
            saveSettings()
        }
    }

    private func currentCatalogItem(for model: InstalledModel) -> ModelCatalogItem? {
        if let byID = catalog.first(where: { $0.id == model.catalogItem.id }) {
            return byID
        }

        switch model.catalogItem.runtimeType {
        case .gguf, .liteRTLM:
            guard let localPath = model.localPath else { return nil }
            let fileName = URL(fileURLWithPath: localPath).lastPathComponent
            return catalog.first {
                $0.runtimeType == model.catalogItem.runtimeType &&
                $0.downloadFileName == fileName
            }
        case .mlx:
            guard let mlxModelID = model.catalogItem.mlxModelID ?? model.localPath else {
                return nil
            }
            return catalog.first {
                $0.runtimeType == .mlx &&
                $0.mlxModelID == mlxModelID
            }
        case .foundationModels:
            return catalog.first { $0.runtimeType == .foundationModels }
        }
    }

    private func reconciledLocalPath(model: InstalledModel, currentCatalogItem: ModelCatalogItem) -> String? {
        switch currentCatalogItem.runtimeType {
        case .gguf:
            return model.localPath
        case .liteRTLM:
            if let localPath = model.localPath,
               FileManager.default.fileExists(atPath: localPath),
               URL(fileURLWithPath: localPath).pathExtension == "litertlm" {
                return localPath
            }
            return URLModelDownloadService.installedLocalPath(for: currentCatalogItem)
        case .mlx:
            return currentCatalogItem.mlxModelID
        case .foundationModels:
            return AppleFoundationModelService.localPathMarker
        }
    }

    private func reconciledInstallState(
        model: InstalledModel,
        currentCatalogItem: ModelCatalogItem,
        reconciledPath: String?
    ) -> InstalledModel.InstallState {
        guard currentCatalogItem.runtimeType == .liteRTLM else {
            return model.installState
        }
        guard let reconciledPath,
              FileManager.default.fileExists(atPath: reconciledPath) else {
            return .notInstalled
        }
        return model.installState
    }

    /// One-time migration for catalog entries that are no longer supported by the shipped runtimes.
    private func migrateUnsupportedCatalogEntriesIfNeeded() {
        let deprecatedModelIDs: Set<String> = [
            "mlx-community/gemma-3n-E2B-it-4bit",
            "mlx-community/gemma-3n-E4B-it-4bit",
            "mlx-community/gemma-3n-E2B-it-lm-4bit",
            "mlx-community/gemma-3n-E4B-it-lm-4bit",
            "mlx-community/gemma-3-4b-it-4bit",
            "mlx-community/gemma-4-e2b-it-4bit",
            "mlx-community/gemma-4-e4b-it-4bit",
            "mlx-community/OpenELM-270M-Instruct-4bit",
            "mlx-community/OpenELM-1_1B-Instruct-4bit",
            "mlx-community/granite-3.3-8b-instruct-4bit",
            "mlx-community/Qwen3-VL-2B-Instruct-4bit",
            "mlx-community/Qwen3-VL-4B-Instruct-4bit",
            "mlx-community/Qwen3-4B-4bit",
            "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            "mlx-community/Qwen3-4B-Thinking-2507-4bit",
            "mlx-community/Qwen3-8B-4bit"
        ]
        let deprecatedLiteRTFileNames: Set<String> = [
            "gemma3-270m-it-q4_0-web.task",
            "gemma3-270m-it-q8-web.task",
            "gemma3-270m-it-q8.task",
            "gemma-3-270m-it.task"
        ]

        var didChange = false
        var migratedDefaultModelID = settings.defaultModelID

        let migrated = installedModels.compactMap { model -> InstalledModel? in
            let oldModelID = model.catalogItem.mlxModelID
            let fileName = model.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            let displayName = model.catalogItem.displayName.lowercased()
            let isDeprecatedMLX = oldModelID.map(deprecatedModelIDs.contains) ?? false
            let isDeprecatedLiteRT = model.catalogItem.runtimeType == .liteRTLM
                && (
                    deprecatedLiteRTFileNames.contains(fileName)
                    || fileName.hasSuffix(".task")
                    || displayName.contains("gemma 3 270m")
                    || displayName.contains("gemma 3 1b")
                )

            guard isDeprecatedMLX || isDeprecatedLiteRT else {
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

    private func ensureSystemFoundationModelAvailable() {
        guard let systemModel = catalog.first(where: { $0.runtimeType == .foundationModels }) else {
            return
        }

        guard !installedModels.contains(where: { $0.catalogItem.id == systemModel.id }) else {
            return
        }

        let shouldMakeDefault = settings.defaultModelID == nil || defaultModel == nil
        if shouldMakeDefault {
            installedModels = installedModels.map { model in
                var updated = model
                updated.isDefault = false
                return updated
            }
            settings.defaultModelID = systemModel.id
        }

        installedModels.insert(
            InstalledModel(
                catalogItem: systemModel,
                installState: .installed,
                progress: 1,
                localPath: AppleFoundationModelService.localPathMarker,
                isDefault: shouldMakeDefault
            ),
            at: 0
        )

        saveInstalledModels()
        saveSettings()
    }
}
