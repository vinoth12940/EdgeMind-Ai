import SwiftUI

enum AppTheme {
    // MARK: - Core Palette (Carbon / Ember / Cyan)
    static let background = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let panelRaised = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let panelHover = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let accent = Color(red: 0.13, green: 0.79, blue: 0.84)
    static let accentSoft = Color(red: 0.85, green: 0.57, blue: 0.34)
    static let accentWarm = Color(red: 1.0, green: 0.41, blue: 0.22)
    static let success = Color(red: 0.37, green: 0.87, blue: 0.49)
    static let warning = Color(red: 1.0, green: 0.70, blue: 0.24)
    static let destructive = Color(red: 1.0, green: 0.33, blue: 0.31)
    static let textPrimary = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let textSecondary = Color(red: 0.75, green: 0.75, blue: 0.77)
    static let textTertiary = Color(red: 0.52, green: 0.52, blue: 0.55)
    static let hairline = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.06)

    // MARK: - Gradients
    static let glow = LinearGradient(
        colors: [accent.opacity(0.5), accentSoft.opacity(0.2), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let meshBackground = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.04, blue: 0.03),
            Color(red: 0.07, green: 0.06, blue: 0.07),
            Color(red: 0.03, green: 0.03, blue: 0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let userBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.18, blue: 0.19),
            Color(red: 0.15, green: 0.15, blue: 0.16)
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
        colors: [panelRaised.opacity(0.95), panel.opacity(0.95)],
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
    static let labIBM = Color(red: 0.35, green: 0.55, blue: 1.00)
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
    static let labMLXCommunity = Color(red: 1.00, green: 0.62, blue: 0.18)

    // MARK: - Capability Colors
    static let capThinking = Color(red: 1.00, green: 0.56, blue: 0.38)
    static let capVision = Color(red: 0.30, green: 0.85, blue: 0.75)
    static let capVideo = Color(red: 0.28, green: 0.78, blue: 0.48)
    static let capAudio = Color(red: 0.97, green: 0.46, blue: 0.62)
    static let capTools = Color(red: 0.98, green: 0.60, blue: 0.20)
    static let capReasoning = Color(red: 0.95, green: 0.85, blue: 0.35)

    static func labColor(for family: ModelCatalogItem.ModelFamily) -> Color {
        switch family {
        case .gemma: return labGoogle
        case .granite: return labIBM
        case .llama: return labMeta
        case .qwen: return labAlibaba
        case .phi: return labMicrosoft
        case .mistral: return labMistral
        case .deepSeek: return labDeepSeek
        case .smolLM, .smolVLM: return labHuggingFace
        case .stableLM: return labStability
        case .openELM, .appleIntelligence: return labApple
        case .tinyLlama: return labStatNLP
        case .lfm: return Color(red: 0.0, green: 0.75, blue: 0.85) // Liquid AI teal
        case .kokoro: return labKokoro
        case .mlxCommunity: return labMLXCommunity
        }
    }

    static func capabilityColor(for cap: ModelCatalogItem.ModelCapability) -> Color {
        switch cap {
        case .thinking: return capThinking
        case .vision: return capVision
        case .video: return capVideo
        case .audio: return capAudio
        case .toolCalling: return capTools
        case .reasoning: return capReasoning
        }
    }
}

struct AppBackdropView: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()

            RoundedRectangle(cornerRadius: 180, style: .continuous)
                .fill(AppTheme.accent.opacity(0.04))
                .frame(width: 340, height: 260)
                .rotationEffect(.degrees(16))
                .blur(radius: 110)
                .offset(x: drift ? -145 : -105, y: -310)

            RoundedRectangle(cornerRadius: 180, style: .continuous)
                .fill(AppTheme.accentSoft.opacity(0.03))
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(-20))
                .blur(radius: 105)
                .offset(x: drift ? 170 : 130, y: -160)

            Circle()
                .fill(AppTheme.accentWarm.opacity(0.02))
                .frame(width: 250, height: 250)
                .blur(radius: 110)
                .offset(x: drift ? 140 : 95, y: 320)

            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear, Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                drift = true
            }
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
                            .fill(AppTheme.panel.opacity(0.74))
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
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
                            .fill(AppTheme.panel.opacity(0.78))
                    )
                    .shadow(color: accentColor.opacity(0.10), radius: 18, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.45), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
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

extension Font {
    static func appDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func appBody(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func appCaps(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}
