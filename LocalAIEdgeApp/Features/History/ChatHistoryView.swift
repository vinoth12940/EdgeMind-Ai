import SwiftUI

struct ChatHistoryView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.selectedTab) private var selectedTab
    @State private var sessionPendingDeletion: ChatSession?
    @State private var showClearHistoryConfirmation = false

    private var totalMessages: Int {
        store.chatSessions.reduce(0) { $0 + $1.messages.count }
    }

    private var destructiveTint: Color {
        Color(red: 1.0, green: 0.31, blue: 0.31)
    }

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historyHero

                    if store.chatSessions.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.chatSessions) { session in
                                sessionCard(session)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 88)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        store.isSidebarOpen.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open history sidebar")
            }
            ToolbarItem(placement: .principal) {
                Text("History")
                    .font(.appDisplay(18))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.createSession(using: store.defaultModel?.catalogItem.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new chat session")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showClearHistoryConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.chatSessions.isEmpty ? AppTheme.textTertiary : destructiveTint)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(store.chatSessions.isEmpty)
                .accessibilityLabel("Delete all chat history")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Delete Conversation", isPresented: deleteConversationBinding) {
            Button("Cancel", role: .cancel) {
                sessionPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionPendingDeletion {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        store.deleteSession(session.id)
                    }
                }
                sessionPendingDeletion = nil
            }
        } message: {
            Text("This removes the selected chat from local history.")
        }
        .alert("Delete All History", isPresented: $showClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    store.deleteAllSessions()
                }
            }
        } message: {
            Text("This removes every saved local conversation on this device.")
        }
    }

    private var deleteConversationBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingDeletion = nil
                }
            }
        )
    }

    private var historyHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Archive")
                        .font(.appDisplay(32))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Jump back into previous local runs, inspect how they ended, and branch into a fresh chat without losing context.")
                        .font(.appBody(14))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    statPill(value: "\(store.chatSessions.count)", label: "Sessions")
                    statPill(value: "\(totalMessages)", label: "Messages")
                }
            }

            HStack(spacing: 10) {
                heroBadge(icon: "lock.shield.fill", text: "On-device history", color: AppTheme.success)
                heroBadge(icon: "clock.arrow.circlepath", text: "Resume instantly", color: AppTheme.warning)
            }
        }
        .padding(.vertical, 8)
        .background(Color.clear)
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.appDisplay(18).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.appCaps(10))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.panelRaised.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func heroBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.appCaps(11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func sessionCard(_ session: ChatSession) -> some View {
        let modelName = store.catalog.first(where: { $0.id == session.modelID })?.displayName ?? "Local session"

        return HStack(spacing: 10) {
            Button {
                store.selectedSessionID = session.id
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectedTab.wrappedValue = 0
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.14))
                            .frame(width: 46, height: 46)
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title)
                            .font(.appDisplay(18))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Text(modelName)
                            .font(.appCaps(11))
                            .foregroundStyle(AppTheme.warning)

                        if let lastMessage = session.messages.last {
                            Text(lastMessage.text)
                                .font(.appBody(13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(session.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.appBody(11))
                            .foregroundStyle(AppTheme.textTertiary)

                        Text("\(session.messages.count)")
                            .font(.appCaps(10))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.panelRaised.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                sessionPendingDeletion = session
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(destructiveTint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(destructiveTint.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(session.title)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button(role: .destructive) {
                sessionPendingDeletion = session
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.accent)

            Text("No conversations yet")
                .font(.appDisplay(20))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Your local sessions will appear here once you start chatting.")
                .font(.appBody(13))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Color.clear)
    }
}
