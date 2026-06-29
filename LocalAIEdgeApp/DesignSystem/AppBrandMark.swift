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

            AngularGradient(
                colors: [
                    AppTheme.accent,
                    AppTheme.accentSoft,
                    AppTheme.accent,
                    AppTheme.accentWarm,
                    AppTheme.accent
                ],
                center: .center
            )
            .mask(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(lineWidth: max(2, size * 0.10))
                    .padding(size * 0.18)
            )

            Circle()
                .fill(AppTheme.accent)
                .frame(width: size * 0.16, height: size * 0.16)

            Circle()
                .fill(AppTheme.accentSoft)
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(x: size * 0.15, y: -size * 0.13)

            Circle()
                .fill(AppTheme.accentWarm)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: -size * 0.14, y: size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
