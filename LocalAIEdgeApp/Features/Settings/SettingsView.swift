import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    privacySection
                    huggingFaceSection
                    behaviorSection
                    webSearchSection
                    backendSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 72)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Sections

    private var huggingFaceSection: some View {
        settingsSection(icon: "face.smiling", title: "HuggingFace", iconColor: .yellow) {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Token")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Required to download gated models (Phi-4, LFM, OpenELM). Get yours at huggingface.co/settings/tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)

                SecureField(
                    "hf_xxxxxxxxxxxxxxxxxx",
                    text: Binding(
                        get: { store.settings.huggingFaceToken },
                        set: { newValue in
                            store.settings.huggingFaceToken = newValue
                            HFTokenManager.token = newValue
                        }
                    )
                )
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )

                if HFTokenManager.hasToken {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.success)
                        Text("Token saved securely in Keychain")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.success)
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        settingsSection(icon: "lock.shield.fill", title: "Privacy", iconColor: AppTheme.success) {
            settingsToggle(
                "Local-first privacy mode",
                isOn: Binding(
                    get: { store.settings.privacyModeEnabled },
                    set: { store.settings.privacyModeEnabled = $0 }
                )
            )

            Divider().foregroundStyle(AppTheme.divider)

            settingsToggle(
                "Enable Live Search by default",
                isOn: Binding(
                    get: { store.settings.useSearchByDefault },
                    set: { store.settings.useSearchByDefault = $0 }
                )
            )
        }
    }

    private var behaviorSection: some View {
        settingsSection(icon: "brain", title: "Behavior", iconColor: AppTheme.accentSoft) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("Custom system prompt…", text: Binding(
                    get: { store.settings.systemPrompt },
                    set: { store.settings.systemPrompt = $0 }
                ), axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(3...6)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
            }

            Divider().foregroundStyle(AppTheme.divider)

            settingsToggle(
                "Voice mode",
                isOn: Binding(
                    get: { store.settings.voiceModeEnabled },
                    set: { store.settings.voiceModeEnabled = $0 }
                )
            )
        }
    }

    private var webSearchSection: some View {
        settingsSection(icon: "globe.americas.fill", title: "Web Search API", iconColor: AppTheme.warning) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: Binding(
                    get: { store.settings.webSearchProvider },
                    set: { store.settings.webSearchProvider = $0 }
                )) {
                    ForEach(AppSettings.WebSearchProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.accent)

                if store.settings.webSearchProvider != .none {
                    Text(store.settings.webSearchProvider.description)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)

                    if store.settings.webSearchProvider != .custom {
                        SecureField(
                            store.settings.webSearchProvider.placeholder,
                            text: Binding(
                                get: { store.settings.webSearchAPIKey },
                                set: { store.settings.webSearchAPIKey = $0 }
                            )
                        )
                        .textContentType(.password)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
                        .background(AppTheme.panelRaised.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        )

                        if !store.settings.webSearchAPIKey.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.success)
                                Text("API key configured")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.success)
                            }
                        }
                    }
                }

                if store.settings.webSearchProvider == .none {
                    Text("Enable a search provider for real-time info. Keys stay on-device.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private var backendSection: some View {
        settingsSection(icon: "server.rack", title: "Backend", iconColor: AppTheme.accent) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Search Gateway URL")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("https://…", text: Binding(
                    get: { store.settings.searchGatewayURL?.absoluteString ?? "" },
                    set: { store.settings.searchGatewayURL = URL(string: $0) }
                ))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )

                Text("Only used when Live Search is enabled.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var aboutSection: some View {
        settingsSection(icon: "info.circle.fill", title: "About", iconColor: AppTheme.textTertiary) {
            HStack {
                Text("Version")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("1.0.0")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Divider().foregroundStyle(AppTheme.divider)

            HStack {
                Text("Runtime")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("llama.cpp · MLX")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .glassCard(cornerRadius: 18, padding: 16)
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .tint(AppTheme.accent)
    }
}
