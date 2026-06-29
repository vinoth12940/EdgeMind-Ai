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
    @Environment(AppStateStore.self) private var store
    @Environment(AuthStateStore.self) private var authStore

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
        ZStack(alignment: .leading) {
            // Main App Container
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
            .disabled(store.isSidebarOpen)

            // Dimming Overlay
            if store.isSidebarOpen {
                AppTheme.scrim
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            store.isSidebarOpen = false
                        }
                    }
                    .transition(.opacity)
            }

            // Slide-out Drawer Panel
            if store.isSidebarOpen {
                sidebarView
                    .transition(.move(edge: .leading))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.isSidebarOpen)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isKeyboardVisible)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFloatingDockHidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onAppear(perform: applyIntentHandoff)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            applyIntentHandoff()
        }
        .onPreferenceChange(FloatingDockHiddenPreferenceKey.self) { hidden in
            isFloatingDockHidden = hidden
        }
    }

    private func applyIntentHandoff() {
        guard let destination = LocalAIIntentHandoffStore.consumeDestination() else { return }
        switch destination {
        case .chat, .voice:
            selectedTab = 0
        case .models:
            selectedTab = 1
        case .diagnostics:
            selectedTab = 3
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
                                colors: [AppTheme.surfaceStroke, AppTheme.cardStroke],
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

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Header
            HStack {
                HStack(spacing: 10) {
                    AppBrandMark(size: 34)
                    Text("EdgeMind")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        store.isSidebarOpen = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // New Chat Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.createSession(using: store.defaultModel?.catalogItem.id)
                    selectedTab = 0
                    store.isSidebarOpen = false
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.background)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppTheme.textPrimary))
                    
                    Text("New Chat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.controlFill)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            
            // Scrollable Recent Chats
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Conversations")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if store.chatSessions.isEmpty {
                            Text("No recent chats")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(store.chatSessions) { session in
                                let isSelected = selectedTab == 0 && store.selectedSession?.id == session.id
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        store.selectedSessionID = session.id
                                        selectedTab = 0
                                        store.isSidebarOpen = false
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 13))
                                            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                                        
                                        Text(session.title)
                                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? AppTheme.selectedFill : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            
            Spacer()
            
            // Bottom Panel Options
            VStack(spacing: 2) {
                Divider().background(AppTheme.divider).padding(.horizontal, 8).padding(.bottom, 6)
                
                sidebarNavItem(icon: "square.stack.3d.up", label: "Model Library") {
                    selectedTab = 1
                    store.isSidebarOpen = false
                }

                sidebarNavItem(icon: "clock.arrow.circlepath", label: "History") {
                    selectedTab = 2
                    store.isSidebarOpen = false
                }
                
                sidebarNavItem(icon: "slider.horizontal.3", label: "Settings") {
                    selectedTab = 3
                    store.isSidebarOpen = false
                }
                
                // User Profile Auth Area
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.controlFill)
                            .frame(width: 32, height: 32)
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authStore.profile?.displayName ?? "Guest User")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(authStore.isAuthenticated ? "Authenticated" : "Local Canvas")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .background(
            AppTheme.panel
                .ignoresSafeArea()
        )
        .overlay(
            Rectangle()
                .fill(AppTheme.surfaceStroke)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func sidebarNavItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
