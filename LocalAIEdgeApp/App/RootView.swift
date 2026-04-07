import SwiftUI

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

    private let tabs: [(icon: String, filledIcon: String, label: String)] = [
        ("bubble.left.and.text.bubble.right", "bubble.left.and.text.bubble.right.fill", "Chat"),
        ("square.stack.3d.up", "square.stack.3d.up.fill", "Models"),
        ("clock.arrow.circlepath", "clock.arrow.circlepath", "History"),
        ("slider.horizontal.3", "slider.horizontal.3", "Settings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: NavigationStack { ChatView() }
                case 1: NavigationStack { ModelLibraryView() }
                case 2: NavigationStack { ChatHistoryView() }
                case 3: NavigationStack { SettingsView() }
                default: EmptyView()
                }
            }
            .environment(\.selectedTab, $selectedTab)

            if !isKeyboardVisible && selectedTab != 0 {
                floatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let isActive = selectedTab == index
                let tab = tabs[index]
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: isActive ? tab.filledIcon : tab.icon)
                            .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textTertiary)
                            .scaleEffect(isActive ? 1.08 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)

                        Text(tab.label)
                            .font(.system(size: 10, weight: isActive ? .bold : .medium))
                            .foregroundStyle(isActive ? AppTheme.textPrimary : AppTheme.textTertiary)
                            .dynamicTypeSize(...DynamicTypeSize.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(AppTheme.panel.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: -6)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
