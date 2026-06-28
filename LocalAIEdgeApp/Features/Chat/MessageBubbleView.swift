import SwiftUI
import ImageIO

struct MessageBubbleView: View {
    let message: ChatMessage

    @State private var thinkingExpanded = false
    @State private var searchExpanded = false

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isRecoveryMessage: Bool { AssistantResponseFallback.isEmptyOutputMessage(message.text) }

    var body: some View {
        switch message.role {
        case .system:
            systemNotice
        case .user:
            userRow
        case .assistant:
            assistantRow
        }
    }

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: 2) {
            VStack(alignment: .leading, spacing: 6) {
                if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !documentAttachments.isEmpty {
                    attachmentChips
                }

                MarkdownTextView(text: message.text, isUser: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.userBubbleGradient)
            )

            messageTimestamp
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 42)
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.citations.isEmpty {
                SearchDisclosureRow(
                    citations: message.citations,
                    isExpanded: $searchExpanded
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 2)
            }

            if let thinkingContent = message.thinkingContent {
                ThinkingDisclosureRow(
                    thinkingContent: thinkingContent,
                    durationSeconds: message.thinkingDurationSeconds,
                    isExpanded: $thinkingExpanded
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 2)
            }

            if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 4)
            }

            if !documentAttachments.isEmpty {
                attachmentChips
                    .padding(.top, 4)
            }

            if isRecoveryMessage {
                recoveryCard
                    .padding(.vertical, 8)
            } else if !message.text.isEmpty {
                MarkdownTextView(text: message.text, isUser: false, citations: message.citations)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            } else if message.thinkingContent != nil && message.thinkingDurationSeconds == nil {
                Color.clear.frame(height: 4)
            }

            messageTimestamp
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
        .padding(.vertical, 4)
    }

    private var documentAttachments: [ChatAttachment] {
        message.attachments.filter { $0.kind != .image }
    }

    private var attachmentChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(documentAttachments) { attachment in
                HStack(spacing: 5) {
                    Image(systemName: icon(for: attachment.kind))
                        .font(.system(size: 10, weight: .bold))
                    Text(attachment.fileName)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isUser ? Color.white.opacity(0.92) : AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(isUser ? 0.16 : 0.06))
                .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private func icon(for kind: ChatAttachment.Kind) -> String {
        switch kind {
        case .image: return "photo"
        case .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .markdown: return "text.alignleft"
        }
    }

    private var systemNotice: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(message.text)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.panelRaised.opacity(0.82))
            .clipShape(Capsule())
            Spacer(minLength: 0)
        }
    }

    private var recoveryCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.warning)
            Text("No visible answer. Try a shorter prompt, switch models, or keep search enabled for live questions.")
                .font(.appBody(13))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var messageTimestamp: some View {
        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.appBody(10))
            .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
            .padding(.horizontal, 4)
    }

    private func previewImage(from data: Data) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - ThinkingDisclosureRow

struct ThinkingDisclosureRow: View {
    let thinkingContent: String
    let durationSeconds: Int?
    @Binding var isExpanded: Bool

    private var isStreaming: Bool { durationSeconds == nil }
    private let thinkingColor = AppTheme.capThinking

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(thinkingColor.opacity(0.18))
                            .frame(width: 20, height: 20)
                        Image(systemName: "lightbulb.max")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(thinkingColor)
                    }

                    if isStreaming {
                        HStack(spacing: 4) {
                            Text("Thinking")
                                .font(.appCaps(11))
                                .foregroundStyle(thinkingColor)
                            ThinkingDotsView()
                        }
                    } else {
                        Text("Thought for \(durationSeconds!)s")
                            .font(.appCaps(11))
                            .foregroundStyle(thinkingColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(thinkingColor.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(thinkingColor.opacity(0.07))
            }
            .buttonStyle(.plain)

            // Expanded body
            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    // Left accent bar
                    Rectangle()
                        .fill(thinkingColor.opacity(0.35))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(thinkingContent + (isStreaming ? "​" : ""))
                            .font(.appBody(12))
                            .italic()
                            .foregroundStyle(thinkingColor.opacity(0.88))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottomTrailing) {
                                if isStreaming {
                                    StreamingCursorView(color: thinkingColor)
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(thinkingColor.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
        }
    }
}

// MARK: - SearchDisclosureRow

struct SearchDisclosureRow: View {
    let citations: [SearchCitation]
    @Binding var isExpanded: Bool

    private let searchColor = Color(red: 0.18, green: 0.78, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(searchColor)

                    Text("Web Search")
                        .font(.appCaps(11))
                        .foregroundStyle(searchColor)

                    Spacer()

                    Text("\(citations.count) source\(citations.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(searchColor.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(searchColor.opacity(0.10))
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(searchColor.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(searchColor.opacity(0.05))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        Link(destination: citation.url) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(searchColor)
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill(searchColor.opacity(0.12)))
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(searchColor)
                                        .lineLimit(1)
                                    if !citation.snippet.isEmpty {
                                        Text(citation.snippet)
                                            .font(.system(size: 10))
                                            .foregroundStyle(AppTheme.textTertiary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(searchColor.opacity(0.4))
                                    .padding(.top, 2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)

                        if index < citations.count - 1 {
                            Divider()
                                .background(searchColor.opacity(0.08))
                                .padding(.leading, 38)
                        }
                    }
                }
                .background(searchColor.opacity(0.02))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.1)
        }
    }
}

// MARK: - Streaming cursor & dots

struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(phase == i ? 1 : 0.3)
                    .scaleEffect(phase == i ? 1.2 : 0.8)
            }
        }
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

struct StreamingCursorView: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: 13)
            .opacity(visible ? 1 : 0)
            .onReceive(Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
