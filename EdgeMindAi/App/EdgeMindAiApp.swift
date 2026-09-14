import SwiftUI

@main
struct EdgeMindAiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AppStateStore
    @State private var authStore = AuthStateStore()
    @State private var chatEngine: ChatTurnEngine
    @State private var memoryStore: MemoryStore
    @State private var documentLibrary = DocumentLibraryStore()

    init() {
        UITabBar.appearance().isHidden = true
        let store = AppStateStore()
        let memoryStore = MemoryStore()
        let documentLibrary = DocumentLibraryStore()
        _store = State(initialValue: store)
        _memoryStore = State(initialValue: memoryStore)
        _documentLibrary = State(initialValue: documentLibrary)
        _chatEngine = State(initialValue: ChatTurnEngine(
            store: store,
            dependencies: .live(memoryStore: memoryStore, documentLibrary: documentLibrary)
        ))
    }

    var body: some Scene {
        WindowGroup {
            LaunchRootView()
            .environment(store)
            .environment(authStore)
            .environment(chatEngine)
            .environment(memoryStore)
            .environment(documentLibrary)
            .preferredColorScheme(store.settings.appearanceMode.preferredColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await RuntimeMemoryCoordinator.releaseAll()
                }
            }
        }
    }
}

private extension AppSettings.AppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

private struct LaunchRootView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(AuthStateStore.self) private var authStore
    @State private var didRunLaunchTasks = false

    var body: some View {
        RootView()
            .onAppear {
                authStore.ensureAnonymousSession()
            }
        .task {
            guard !didRunLaunchTasks else { return }
            didRunLaunchTasks = true
            await HeadlessModelAuditLauncher.runIfRequested(store: store)
        }
    }
}
