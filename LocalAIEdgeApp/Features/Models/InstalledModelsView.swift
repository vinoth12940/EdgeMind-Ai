import SwiftUI

struct InstalledModelsView: View {
    let installedModels: [InstalledModel]
    let onSelectDefault: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                Text("Installed Models")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if installedModels.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("No models installed yet")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .glassCard()
            } else {
                ForEach(installedModels) { model in
                    installedCard(model)
                }
            }
        }
    }

    private func installedCard(_ model: InstalledModel) -> some View {
        let labColor = AppTheme.labColor(for: model.catalogItem.family)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(labColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.catalogItem.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(model.catalogItem.parameterSize)
                        .font(.caption2.weight(.semibold))
                    Text("•")
                    Text(model.catalogItem.contextWindow + " ctx")
                        .font(.caption2)
                    if !model.catalogItem.capabilities.isEmpty {
                        Text("•")
                        ForEach(model.catalogItem.capabilities, id: \.self) { cap in
                            Image(systemName: cap.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(AppTheme.capabilityColor(for: cap))
                        }
                    }
                }
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button(model.isDefault ? "Default" : "Use") {
                onSelectDefault(model.catalogItem.id)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(model.isDefault ? AppTheme.success.opacity(0.2) : AppTheme.accent.opacity(0.15))
            .foregroundStyle(model.isDefault ? AppTheme.success : AppTheme.accent)
            .clipShape(Capsule())
        }
        .accentGlassCard(model.isDefault ? AppTheme.success : labColor)
    }
}
