import SwiftUI

@main
struct EdgeMindAiApp: App {
    @State private var store = AppStateStore()
    @State private var authStore = AuthStateStore()

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            LaunchRootView()
            .environment(store)
            .environment(authStore)
            .preferredColorScheme(store.settings.appearanceMode.preferredColorScheme)
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
