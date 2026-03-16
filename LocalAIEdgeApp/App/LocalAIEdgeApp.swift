import SwiftUI

@main
struct LocalAIEdgeApp: App {
    @State private var store = AppStateStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
