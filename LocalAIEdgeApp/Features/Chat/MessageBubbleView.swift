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
                        MarkdownTextView(text: message.text, isUser: false)
                            .textSelection(.enabled)
                    }

                    if !message.citations.isEmpty {
                        citationsView
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .overlay(
                    bubbleShape
                        .stroke(isUser ? Color.clear : AppTheme.hairline, lineWidth: 1)
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
            Circle()
                .fill(avatarBackground)
                .frame(width: 30, height: 30)

            Image(systemName: avatarIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(avatarForeground)
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
        case .user: return AnyShapeStyle(AppTheme.accent.opacity(0.15))
        case .assistant: return AnyShapeStyle(AppTheme.accentSoft.opacity(0.12))
        case .search: return AnyShapeStyle(AppTheme.warning.opacity(0.12))
        case .system: return AnyShapeStyle(AppTheme.panel)
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
            return AnyShapeStyle(AppTheme.userBubbleGradient)
        case .assistant:
            return AnyShapeStyle(AppTheme.panel.opacity(0.9))
        case .search:
            return AnyShapeStyle(AppTheme.panelRaised)
        case .system:
            return AnyShapeStyle(AppTheme.panel.opacity(0.6))
        }
    }

    // MARK: - Citations

    private var citationsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                Text("Sources")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(AppTheme.textTertiary)

            ForEach(message.citations) { citation in
                Link(destination: citation.url) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.4))
                            .frame(width: 3, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(citation.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1)
                            Text(citation.snippet)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.panelRaised.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
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
