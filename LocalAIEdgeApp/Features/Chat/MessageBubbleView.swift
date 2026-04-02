import SwiftUI
import ImageIO

struct MessageBubbleView: View {
    let message: ChatMessage

    @State private var thinkingExpanded = false
    @State private var searchExpanded = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                roleAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Bubble
                if isUser || message.role == .search || message.role == .system {
                    // User / legacy search / system — plain text, padded
                    VStack(alignment: .leading, spacing: 10) {
                        if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220, maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        MarkdownTextView(text: message.text, isUser: isUser)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleBackground)
                    .clipShape(bubbleShape)
                    .overlay(bubbleBorder)
                    .shadow(
                        color: isUser ? AppTheme.accent.opacity(0.25) : .black.opacity(0.15),
                        radius: isUser ? 12 : 6, x: 0, y: isUser ? 4 : 2
                    )
                } else {
                    // Assistant — with optional thinking + search disclosure rows
                    VStack(alignment: .leading, spacing: 0) {
                        // Search row (search fires before inference — always at top)
                        if !message.citations.isEmpty {
                            SearchDisclosureRow(
                                citations: message.citations,
                                isExpanded: $searchExpanded
                            )
                        }

                        // Thinking row (thinking models only)
                        if let thinkingContent = message.thinkingContent {
                            ThinkingDisclosureRow(
                                thinkingContent: thinkingContent,
                                durationSeconds: message.thinkingDurationSeconds,
                                isExpanded: $thinkingExpanded
                            )
                        }

                        // Attached image
                        if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220, maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal, 14)
                                .padding(.top, 11)
                        }

                        // Answer text
                        if !message.text.isEmpty {
                            MarkdownTextView(text: message.text, isUser: false, citations: message.citations)
                                .textSelection(.enabled)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        } else if message.thinkingContent != nil && message.thinkingDurationSeconds == nil {
                            // Still inside <think> — show nothing in the answer area yet
                            Color.clear.frame(height: 4)
                        }
                    }
                    .background(bubbleBackground)
                    .clipShape(bubbleShape)
                    .overlay(bubbleBorder)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                }

                // Timestamp
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 4)
            }

            if isUser {
                roleAvatar
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var bubbleBorder: some View {
        bubbleShape
            .stroke(
                isUser
                    ? LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                lineWidth: 1
            )
    }

    // MARK: - Avatar

    private var roleAvatar: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            avatarGlowColor.opacity(0.4),
                            avatarGlowColor.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .blur(radius: 8)
            
            // Main circle
            Circle()
                .fill(avatarBackground)
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .stroke(avatarBorderColor, lineWidth: 1.5)
                )

            Image(systemName: avatarIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(avatarForeground)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }
    
    private var avatarGlowColor: Color {
        switch message.role {
        case .user: return AppTheme.accent
        case .assistant: return AppTheme.accentSoft
        case .search: return AppTheme.warning
        case .system: return Color.clear
        }
    }
    
    private var avatarBorderColor: Color {
        switch message.role {
        case .user: return AppTheme.accent.opacity(0.4)
        case .assistant: return AppTheme.accentSoft.opacity(0.3)
        case .search: return AppTheme.warning.opacity(0.3)
        case .system: return Color.white.opacity(0.1)
        }
    }

    private var avatarIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .search: return "globe"
        case .system: return "gearshape.fill"
        }
    }

    private var avatarBackground: some ShapeStyle {
        switch message.role {
        case .user: 
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.25), AppTheme.accent.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .assistant: 
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppTheme.accentSoft.opacity(0.2), AppTheme.accentSoft.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .search: 
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppTheme.warning.opacity(0.2), AppTheme.warning.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .system: 
            return AnyShapeStyle(Color(red: 0.10, green: 0.12, blue: 0.17))
        }
    }

    private var avatarForeground: Color {
        switch message.role {
        case .user: return AppTheme.accent
        case .assistant: return AppTheme.accentSoft
        case .search: return AppTheme.warning
        case .system: return AppTheme.textSecondary
        }
    }

    // MARK: - Bubble

    private var bubbleShape: UnevenRoundedRectangle {
        if isUser {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 6, topTrailing: 18),
                style: .continuous
            )
        } else {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 6, bottomLeading: 18, bottomTrailing: 18, topTrailing: 18),
                style: .continuous
            )
        }
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.75, blue: 1.0),
                        Color(red: 0.34, green: 0.44, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .assistant:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.12, blue: 0.18),
                        Color(red: 0.08, green: 0.10, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .search:
            return AnyShapeStyle(
                Color(red: 0.12, green: 0.14, blue: 0.20)
            )
        case .system:
            return AnyShapeStyle(AppTheme.panel.opacity(0.6))
        }
    }

    // MARK: - Citations (compact clickable pills)

    private var compactCitationsView: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(message.citations.enumerated()), id: \.element.id) { index, citation in
                Link(destination: citation.url) {
                    HStack(spacing: 4) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(AppTheme.accent.opacity(0.7))
                            )

                        Text(citation.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var citationsView: some View {
        compactCitationsView
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
                            .fill(Color(red: 0.66, green: 0.33, blue: 0.98).opacity(0.18))
                            .frame(width: 20, height: 20)
                        Image(systemName: "lightbulb.max")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.75, green: 0.50, blue: 0.98))
                    }

                    if isStreaming {
                        HStack(spacing: 4) {
                            Text("Thinking")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.75, green: 0.50, blue: 0.98))
                            ThinkingDotsView()
                        }
                    } else {
                        Text("Thought for \(durationSeconds!)s")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.75, green: 0.50, blue: 0.98))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.49, green: 0.24, blue: 0.86).opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.66, green: 0.33, blue: 0.98).opacity(0.07))
            }
            .buttonStyle(.plain)

            // Expanded body
            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    // Left accent bar
                    Rectangle()
                        .fill(Color(red: 0.66, green: 0.33, blue: 0.98).opacity(0.35))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(thinkingContent + (isStreaming ? "​" : ""))
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .italic()
                            .foregroundStyle(Color(red: 0.62, green: 0.48, blue: 0.85))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottomTrailing) {
                                if isStreaming {
                                    StreamingCursorView(color: Color(red: 0.75, green: 0.50, blue: 0.98))
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(red: 0.66, green: 0.33, blue: 0.98).opacity(0.04))
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
                            .fill(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.18))
                            .frame(width: 20, height: 20)
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75))
                    }

                    Text("Web Search")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75))

                    Spacer()

                    // Source count pill
                    Text("\(citations.count) source\(citations.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.25), lineWidth: 0.5)
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.06))
            }
            .buttonStyle(.plain)

            // Expanded source list
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        Link(destination: citation.url) {
                            HStack(alignment: .top, spacing: 10) {
                                // Index badge
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                                    .frame(width: 16, height: 16)
                                    .background(
                                        Circle()
                                            .fill(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.18))
                                    )
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.18, green: 0.83, blue: 0.75))
                                        .lineLimit(1)
                                    if !citation.snippet.isEmpty {
                                        Text(citation.snippet)
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.5))
                                    .padding(.top, 2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                index % 2 == 0
                                    ? Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.03)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        if index < citations.count - 1 {
                            Divider()
                                .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.1))
                                .padding(.leading, 38)
                        }
                    }
                }
                .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.03))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
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
                    .fill(Color(red: 0.75, green: 0.50, blue: 0.98))
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.3)
                    .scaleEffect(phase == i ? 1.2 : 0.8)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
                // Driven by timer below
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
