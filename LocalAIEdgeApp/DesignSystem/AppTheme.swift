import SwiftUI

enum AppTheme {
    // MARK: - Core Palette
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let panel = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let panelRaised = Color(red: 0.10, green: 0.12, blue: 0.17)
    static let panelHover = Color(red: 0.13, green: 0.15, blue: 0.21)
    static let accent = Color(red: 0.20, green: 0.72, blue: 1.0)
    static let accentSoft = Color(red: 0.34, green: 0.44, blue: 0.98)
    static let success = Color(red: 0.22, green: 0.82, blue: 0.56)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.28)
    static let destructive = Color(red: 0.95, green: 0.30, blue: 0.35)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.30)
    static let hairline = Color.white.opacity(0.06)
    static let divider = Color.white.opacity(0.04)

    // MARK: - Gradients
    static let glow = LinearGradient(
        colors: [accent.opacity(0.6), accentSoft.opacity(0.25), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshBackground = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.04, blue: 0.12),
            Color(red: 0.03, green: 0.06, blue: 0.10),
            Color(red: 0.04, green: 0.04, blue: 0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let userBubbleGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGlow = LinearGradient(
        colors: [accent.opacity(0.08), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Shadows
    static let softShadow = Color.black.opacity(0.45)
    static let glowShadow = accent.opacity(0.2)

    // MARK: - Lab Colors
    static let labGoogle = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let labMeta = Color(red: 0.10, green: 0.47, blue: 0.95)
    static let labAlibaba = Color(red: 1.00, green: 0.42, blue: 0.00)
    static let labMicrosoft = Color(red: 0.00, green: 0.74, blue: 0.95)
    static let labMistral = Color(red: 0.97, green: 0.82, blue: 0.27)
    static let labDeepSeek = Color(red: 0.30, green: 0.42, blue: 1.0)
    static let labHuggingFace = Color(red: 1.00, green: 0.82, blue: 0.12)
    static let labStability = Color(red: 0.67, green: 0.36, blue: 0.82)
    static let labApple = Color(red: 0.64, green: 0.67, blue: 0.68)
    static let labStatNLP = Color(red: 0.40, green: 0.73, blue: 0.42)

    // MARK: - Capability Colors
    static let capThinking = Color(red: 0.95, green: 0.45, blue: 0.95)
    static let capVision = Color(red: 0.30, green: 0.85, blue: 0.75)
    static let capTools = Color(red: 0.98, green: 0.60, blue: 0.20)
    static let capReasoning = Color(red: 0.95, green: 0.85, blue: 0.35)

    static func labColor(for family: ModelCatalogItem.ModelFamily) -> Color {
        switch family {
        case .gemma: return labGoogle
        case .llama: return labMeta
        case .qwen: return labAlibaba
        case .phi: return labMicrosoft
        case .mistral: return labMistral
        case .deepSeek: return labDeepSeek
        case .smolLM, .smolVLM: return labHuggingFace
        case .stableLM: return labStability
        case .openELM: return labApple
        case .tinyLlama: return labStatNLP
        case .lfm: return Color(red: 0.0, green: 0.75, blue: 0.85) // Liquid AI teal
        }
    }

    static func capabilityColor(for cap: ModelCatalogItem.ModelCapability) -> Color {
        switch cap {
        case .thinking: return capThinking
        case .vision: return capVision
        case .toolCalling: return capTools
        case .reasoning: return capReasoning
        }
    }
}

// MARK: - View Modifiers

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.panel.opacity(0.85))
                    .shadow(color: AppTheme.softShadow, radius: 16, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AccentGlassCardModifier: ViewModifier {
    let accentColor: Color
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.panel.opacity(0.9))
                    .shadow(color: accentColor.opacity(0.08), radius: 12, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.45), AppTheme.hairline],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Typing dots animation
struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(AppTheme.accent.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(dotScale(for: i))
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear { phase = 1 }
    }

    private func dotScale(for index: Int) -> CGFloat {
        phase == 0 ? 0.5 : 1.0
    }
}

/// Shimmer loading placeholder
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

/// Pulsing glow ring
struct PulseGlow: ViewModifier {
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.5 : 0.15), radius: isPulsing ? 12 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func accentGlassCard(_ color: Color, cornerRadius: CGFloat = 20) -> some View {
        modifier(AccentGlassCardModifier(accentColor: color, cornerRadius: cornerRadius))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func pulseGlow(_ color: Color) -> some View {
        modifier(PulseGlow(color: color))
    }
}
