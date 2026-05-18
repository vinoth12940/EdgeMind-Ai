import SwiftUI

private struct FloatingDockHiddenPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func floatingDockHidden(_ hidden: Bool = true) -> some View {
        preference(key: FloatingDockHiddenPreferenceKey.self, value: hidden)
    }
}

struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

struct RootView: View {
    @State private var selectedTab = 0
    @State private var isKeyboardVisible = false
    @State private var isFloatingDockHidden = false

    private let tabs: [(icon: String, filledIcon: String, label: String)] = [
        ("bubble.left.and.text.bubble.right", "bubble.left.and.text.bubble.right.fill", "Chat"),
        ("square.stack.3d.up", "square.stack.3d.up.fill", "Models"),
        ("clock.arrow.circlepath", "clock.arrow.circlepath", "History"),
        ("slider.horizontal.3", "slider.horizontal.3", "Settings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackdropView()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    ChatView()
                        .toolbar(.hidden, for: .tabBar)
                }
                    .tag(0)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }

                NavigationStack {
                    ModelLibraryView()
                        .toolbar(.hidden, for: .tabBar)
                }
                    .tag(1)
                    .tabItem { Label("Models", systemImage: "square.stack.3d.up") }

                NavigationStack {
                    ChatHistoryView()
                        .toolbar(.hidden, for: .tabBar)
                }
                    .tag(2)
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

                NavigationStack {
                    SettingsView()
                        .toolbar(.hidden, for: .tabBar)
                }
                    .tag(3)
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
            .toolbar(.hidden, for: .tabBar)
            .environment(\.selectedTab, $selectedTab)
            .font(.appBody(15))

            if !isKeyboardVisible && selectedTab != 0 && !isFloatingDockHidden {
                floatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isKeyboardVisible)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFloatingDockHidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onPreferenceChange(FloatingDockHiddenPreferenceKey.self) { hidden in
            isFloatingDockHidden = hidden
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let isActive = selectedTab == index
                let tab = tabs[index]
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab = index
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isActive ? tab.filledIcon : tab.icon)
                            .font(.system(size: 16, weight: isActive ? .bold : .semibold))
                            .foregroundStyle(isActive ? AppTheme.background : AppTheme.textSecondary)

                        if isActive {
                            Text(tab.label)
                                .font(.appCaps(12))
                                .foregroundStyle(AppTheme.background)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background {
                        if isActive {
                            Capsule(style: .continuous)
                                .fill(AppTheme.accentGradient)
                                .shadow(color: AppTheme.accent.opacity(0.45), radius: 8, x: 0, y: 4)
                        }
                    }
                }
                .accessibilityLabel(tab.label)
            }
        }
        .padding(8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(AppTheme.dockGradient.opacity(0.86))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.50), radius: 34, x: 0, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
