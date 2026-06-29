import SwiftUI

struct TabSwitcherMenuButton: View {
    @Environment(\.selectedTab) private var selectedTab

    var accessibilityLabel: String = "Open tab menu"

    var body: some View {
        Menu {
            tabButton("Chat", systemImage: "bubble.left.and.text.bubble.right", index: 0)
            tabButton("Models", systemImage: "square.stack.3d.up", index: 1)
            tabButton("History", systemImage: "clock.arrow.circlepath", index: 2)
            tabButton("Settings", systemImage: "slider.horizontal.3", index: 3)
        } label: {
            ZStack {
                Circle()
                    .fill(AppTheme.panelRaised.opacity(0.9))
                    .frame(width: 34, height: 34)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func tabButton(_ title: String, systemImage: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                selectedTab.wrappedValue = index
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
