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
        ("message", "message.fill", "Chat"),
        ("square.stack.3d.up", "square.stack.3d.up.fill", "Models"),
        ("clock", "clock.fill", "History"),
        ("gearshape", "gearshape.fill", "Settings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
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

            // Floating tab bar
            if !isKeyboardVisible {
                floatingTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isKeyboardVisible)
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isActive {
                                Circle()
                                    .fill(AppTheme.accent.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                    .transition(.scale.combined(with: .opacity))
                            }

                            Image(systemName: isActive ? tabs[index].filledIcon : tabs[index].icon)
                                .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textTertiary)
                        }
                        .frame(width: 40, height: 40)

                        Text(tab.label)
                            .font(.system(size: 10, weight: isActive ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textTertiary)
                            .dynamicTypeSize(...DynamicTypeSize.large)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.panel.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .shadow(color: AppTheme.softShadow, radius: 24, x: 0, y: -4)
                .shadow(color: Color.black.opacity(0.08), radius: 32, x: 0, y: -8)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }
}
