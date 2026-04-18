import SwiftUI

enum AppTheme {
    // MARK: - Core Palette (Obsidian / Neon Tide)
    static let background = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let panel = Color(red: 0.05, green: 0.07, blue: 0.10)
    static let panelRaised = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let panelHover = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.24, green: 0.82, blue: 1.0)
    static let accentSoft = Color(red: 0.38, green: 0.94, blue: 0.76)
    static let accentWarm = Color(red: 1.0, green: 0.60, blue: 0.32)
    static let success = Color(red: 0.20, green: 0.88, blue: 0.62)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let destructive = Color(red: 1.0, green: 0.34, blue: 0.38)
    static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let textSecondary = Color.white.opacity(0.50)
    static let textTertiary = Color.white.opacity(0.26)
    static let hairline = Color.white.opacity(0.07)
    static let divider = Color.white.opacity(0.04)

    // MARK: - Gradients
    static let glow = LinearGradient(
        colors: [accent.opacity(0.5), accentSoft.opacity(0.2), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshBackground = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.08),
            Color(red: 0.02, green: 0.08, blue: 0.11),
            Color(red: 0.02, green: 0.03, blue: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let userBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.61, blue: 0.98),
            Color(red: 0.14, green: 0.84, blue: 0.78)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGlow = LinearGradient(
        colors: [accent.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let accentGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [panel, panelRaised.opacity(0.78)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let dockGradient = LinearGradient(
        colors: [panelRaised.opacity(0.94), panel.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let heroGradient = LinearGradient(
        colors: [
            accent.opacity(0.20),
            accentSoft.opacity(0.14),
            accentWarm.opacity(0.10),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadows
    static let softShadow = Color.black.opacity(0.50)
    static let glowShadow = accent.opacity(0.15)

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
    static let labKokoro = Color(red: 0.97, green: 0.46, blue: 0.62)

    // MARK: - Capability Colors
    static let capThinking = Color(red: 1.00, green: 0.56, blue: 0.38)
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
        case .kokoro: return labKokoro
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

struct AppBackdropView: View {
    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()

            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 130)
                .offset(x: -120, y: -300)

            Circle()
                .fill(AppTheme.accentSoft.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 120)
                .offset(x: 150, y: -180)

            Circle()
                .fill(AppTheme.accentWarm.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 120)
                .offset(x: 120, y: 330)

            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear, Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()
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
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppTheme.panel.opacity(0.6))
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
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
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppTheme.panel.opacity(0.65))
                    )
                    .shadow(color: accentColor.opacity(0.06), radius: 16, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.35), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
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
    @State private var phase: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.06), Color.white.opacity(0.10), Color.white.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 200)
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 400
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
            .shadow(color: color.opacity(isPulsing ? 0.4 : 0.10), radius: isPulsing ? 16 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
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
