import SwiftUI

@main
struct LocalAIEdgeApp: App {
    @State private var store = AppStateStore()
    @State private var authStore = AuthStateStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if authStore.isAuthenticated {
                    RootView()
                } else {
                    AuthLandingView()
                }
            }
                .environment(store)
                .environment(authStore)
                .preferredColorScheme(.dark)
        }
    }
}
