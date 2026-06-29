import SwiftUI

struct AppBrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: max(0.5, size * 0.018))
            }
            .shadow(color: AppTheme.accent.opacity(0.18), radius: size * 0.12, y: size * 0.04)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
