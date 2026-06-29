import SwiftUI

struct AppBrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.12, blue: 0.14),
                            Color(red: 0.10, green: 0.18, blue: 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.22))
                        .frame(width: size * 0.72, height: size * 0.72)
                        .blur(radius: size * 0.10)
                        .offset(x: size * 0.18, y: -size * 0.20)
                }

            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentWarm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.5, size * 0.075)
                )
                .padding(size * 0.12)

            Text("AI")
                .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            neuralNode(color: AppTheme.accent, scale: 0.12)
                .offset(x: -size * 0.30, y: -size * 0.28)
            neuralNode(color: AppTheme.accentSoft, scale: 0.09)
                .offset(x: size * 0.31, y: -size * 0.25)
            neuralNode(color: AppTheme.accentWarm, scale: 0.09)
                .offset(x: size * 0.28, y: size * 0.30)
            neuralNode(color: AppTheme.accent, scale: 0.075)
                .offset(x: -size * 0.26, y: size * 0.27)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func neuralNode(color: Color, scale: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * scale, height: size * scale)
            .shadow(color: color.opacity(0.55), radius: size * 0.04)
    }
}
