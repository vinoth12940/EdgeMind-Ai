import SwiftUI
import ImageIO

struct MessageBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                roleAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Bubble
                VStack(alignment: .leading, spacing: 10) {
                    // Attached image
                    if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if isUser || message.role == .search || message.role == .system {
                        Text(message.text)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(isUser ? .white : AppTheme.textPrimary)
                            .textSelection(.enabled)
                    } else {
                        MarkdownTextView(text: message.text, isUser: false, citations: message.citations)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .overlay(
                    bubbleShape
                        .stroke(
                            isUser 
                                ? LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isUser ? AppTheme.accent.opacity(0.25) : .black.opacity(0.15),
                    radius: isUser ? 12 : 6,
                    x: 0,
                    y: isUser ? 4 : 2
                )

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
