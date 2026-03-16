import SwiftUI

struct ChatHistoryView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.selectedTab) private var selectedTab

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()

            if store.chatSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.chatSessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 72)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("History")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.createSession(using: store.defaultModel?.catalogItem.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(8)
                        .background(AppTheme.panel.opacity(0.6))
                        .clipShape(Circle())
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func sessionCard(_ session: ChatSession) -> some View {
        Button {
            store.selectedSessionID = session.id
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab.wrappedValue = 0
            }
        } label: {
            HStack(spacing: 14) {
                // Leading icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if let lastMessage = session.messages.last {
                        Text(lastMessage.text)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)

                    Text("\(session.messages.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.panelRaised)
                        .clipShape(Capsule())
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.panel.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
        .contextMenu {
            Button(role: .destructive) {
                store.deleteSession(session.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft.opacity(0.06))
                    .frame(width: 80, height: 80)
                Image(systemName: "clock")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Text("No conversations yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Your chat history will appear here")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}
