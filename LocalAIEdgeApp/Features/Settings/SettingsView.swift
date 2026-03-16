import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.selectedTab) private var selectedTab

    private var selectedVoiceAsset: InstalledModel? {
        store.installedModels.first(where: {
            $0.installState == .installed &&
            $0.catalogItem.primaryUse == .voice &&
            $0.catalogItem.displayName == store.settings.voiceModel.catalogDisplayName
        })
    }

    private var isSelectedVoiceAssetInstalled: Bool {
        selectedVoiceAsset != nil
    }

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
                            store.persistSettings()
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
                    set: {
                        store.settings.privacyModeEnabled = $0
                        store.persistSettings()
                    }
                )
            )

            Divider().foregroundStyle(AppTheme.divider)

            settingsToggle(
                "Enable Live Search by default",
                isOn: Binding(
                    get: { store.settings.useSearchByDefault },
                    set: {
                        store.settings.useSearchByDefault = $0
                        store.persistSettings()
                    }
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
                    set: {
                        store.settings.systemPrompt = $0
                        store.persistSettings()
                    }
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
                    set: {
                        store.settings.voiceModeEnabled = $0
                        store.persistSettings()
                    }
                )
            )

            if store.settings.voiceModeEnabled {
                Divider().foregroundStyle(AppTheme.divider)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Voice Model")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Picker("Voice Model", selection: Binding(
                        get: { store.settings.voiceModel },
                        set: {
                            store.settings.voiceModel = $0
                            store.persistSettings()
                        }
                    )) {
                        ForEach(AppSettings.VoiceModel.allCases, id: \.self) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accent)

                    Text(store.settings.voiceModel.description)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)

                    HStack(spacing: 6) {
                        Image(systemName: isSelectedVoiceAssetInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelectedVoiceAssetInstalled ? AppTheme.success : AppTheme.warning)

                        Text(isSelectedVoiceAssetInstalled ? "Kokoro asset downloaded" : "Kokoro asset not downloaded yet")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelectedVoiceAssetInstalled ? AppTheme.success : AppTheme.warning)

                        Spacer()

                        Button(isSelectedVoiceAssetInstalled ? "Library" : "Download") {
                            selectedTab.wrappedValue = 1
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    }

                    Text("Voice chat already works on-device through Apple Speech: tap the mic in chat to dictate, and enable auto-play to hear replies. The Kokoro download is exposed here as the dedicated voice asset path for future native MLX synthesis.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Divider().foregroundStyle(AppTheme.divider)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Voice Preset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Picker("Voice Preset", selection: Binding(
                        get: { store.settings.voicePreset },
                        set: {
                            store.settings.voicePreset = $0
                            store.persistSettings()
                        }
                    )) {
                        ForEach(AppSettings.VoicePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(store.settings.voicePreset.description)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Divider().foregroundStyle(AppTheme.divider)

                settingsToggle(
                    "Auto-play spoken replies",
                    isOn: Binding(
                        get: { store.settings.autoPlayVoiceResponses },
                        set: {
                            store.settings.autoPlayVoiceResponses = $0
                            store.persistSettings()
                        }
                    )
                )

                Divider().foregroundStyle(AppTheme.divider)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Reply Speed")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer()

                        Text(String(format: "%.2fx", store.settings.voiceResponseRate))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Slider(
                        value: Binding(
                            get: { store.settings.voiceResponseRate },
                            set: {
                                store.settings.voiceResponseRate = $0
                                store.persistSettings()
                            }
                        ),
                        in: 0.8...1.25,
                        step: 0.05
                    )
                    .tint(AppTheme.accent)

                    Text("Playback uses Apple's on-device speech voice today and applies your chosen pace and tone. Kokoro remains the downloadable voice asset selection in the library.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private var webSearchSection: some View {
        settingsSection(icon: "globe.americas.fill", title: "Web Search API", iconColor: AppTheme.warning) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: Binding(
                    get: { store.settings.webSearchProvider },
                    set: {
                        store.settings.webSearchProvider = $0
                        store.persistSettings()
                    }
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
                                set: {
                                    store.settings.webSearchAPIKey = $0
                                    store.persistSettings()
                                }
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
                    set: {
                        store.settings.searchGatewayURL = URL(string: $0)
                        store.persistSettings()
                    }
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
