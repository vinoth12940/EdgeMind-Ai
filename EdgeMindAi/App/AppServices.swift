import Foundation

/// Shared, app-level object graph. Created by `EdgeMindAiApp` and also reachable
/// from App Intents that run in the background, so a Shortcut can answer without
/// the UI (spec §4).
@MainActor
final class AppServices {
    static var shared: AppServices?

    let store: AppStateStore
    let engine: ChatTurnEngine
    let memoryStore: MemoryStore
    let documentLibrary: DocumentLibraryStore

    init(
        store: AppStateStore,
        engine: ChatTurnEngine,
        memoryStore: MemoryStore,
        documentLibrary: DocumentLibraryStore
    ) {
        self.store = store
        self.engine = engine
        self.memoryStore = memoryStore
        self.documentLibrary = documentLibrary
    }
}
