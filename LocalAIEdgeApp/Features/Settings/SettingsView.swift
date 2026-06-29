import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(AuthStateStore.self) private var authStore
    @Environment(\.selectedTab) private var selectedTab
    @State private var isReauthenticating = false
    @State private var hfTokenDraft = ""
    @State private var tokenDebounceTask: Task<Void, Never>?
    @State private var showingPrivacyPolicy = false

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
            AppBackdropView()

            ScrollView {
                VStack(spacing: 20) {
                    profileSection

                    settingsGroupCard(icon: "paintpalette.fill", title: "Appearance", iconColor: AppTheme.accent) {
                        appearanceSectionContent
                    }
                    
                    settingsGroupCard(icon: "brain.head.profile", title: "AI Configuration", iconColor: AppTheme.accentSoft) {
                        behaviorSectionContent
                    }
                    
                    settingsGroupCard(icon: "globe.americas.fill", title: "Search & Integration", iconColor: AppTheme.warning) {
                        huggingFaceSectionContent
                        Divider().foregroundStyle(AppTheme.divider)
                        webSearchSectionContent
                        Divider().foregroundStyle(AppTheme.divider)
                        backendSectionContent
                    }
                    
                    settingsGroupCard(icon: "lock.shield.fill", title: "Privacy", iconColor: AppTheme.success) {
                        privacySectionContent
                    }
                    
                    settingsGroupCard(icon: "info.circle.fill", title: "System & Info", iconColor: AppTheme.textTertiary) {
                        aboutSectionContent
                        Divider().foregroundStyle(AppTheme.divider)
                        developerSectionContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .padding(.bottom, 72)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        store.isSidebarOpen.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open history sidebar")
            }
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.appDisplay(18))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            hfTokenDraft = store.settings.huggingFaceToken
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyExplainerView()
            }
        }
    }

    // MARK: - Grouped Card Container

    private func settingsGroupCard<Content: View>(
        icon: String,
        title: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.7)
        )
    }

    // MARK: - Sections

    private var profileSection: some View {
        settingsGroupCard(icon: "person.crop.circle.fill", title: "Profile", iconColor: AppTheme.accent) {
            profileSectionContent
        }
    }

    @ViewBuilder
    private var appearanceSectionContent: some View {
        Picker("Appearance", selection: Binding(
            get: { store.settings.appearanceMode },
            set: {
                store.settings.appearanceMode = $0
                store.persistSettings()
            }
        )) {
            ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(AppTheme.accent)

        HStack(spacing: 8) {
            Image(systemName: store.settings.appearanceMode.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(store.settings.appearanceMode.description)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    @ViewBuilder
    private var profileSectionContent: some View {
        if let profile = authStore.profile {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if let email = profile.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Text("No email linked")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Spacer()
            }

            HStack {
                Text("Sign-in Method")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(profile.authMethod.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            HStack {
                Text("Last Login")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(profile.lastLoginAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if authStore.canUseDeviceAuthentication {
                Divider().foregroundStyle(AppTheme.divider)

                Button {
                    guard !isReauthenticating else { return }
                    isReauthenticating = true
                    Task {
                        _ = await authStore.reauthenticateCurrentUser()
                        await MainActor.run {
                            isReauthenticating = false
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                        Text(isReauthenticating ? "Authenticating..." : "Re-authenticate with \(authStore.deviceAuthLabel)")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.success)
                }
                .disabled(isReauthenticating)
            }

            Divider().foregroundStyle(AppTheme.divider)

            Button(role: .destructive) {
                authStore.signOut()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("Reset Local Profile")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .font(.system(size: 13))
            }
        } else {
            Text("No profile available.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var huggingFaceSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Token")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Required to download gated Hugging Face models. Get yours at huggingface.co/settings/tokens")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)

            SecureField(
                "hf_xxxxxxxxxxxxxxxxxx",
                text: $hfTokenDraft
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
            .onChange(of: hfTokenDraft) { _, newValue in
                tokenDebounceTask?.cancel()
                tokenDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        store.settings.huggingFaceToken = newValue
                        HFTokenManager.token = newValue
                        store.persistSettings()
                    }
                }
            }

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

    @ViewBuilder
    private var privacySectionContent: some View {
        Button {
            showingPrivacyPolicy = true
        } label: {
            HStack {
                Label("Privacy Policy", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy Policy")

        Divider().foregroundStyle(AppTheme.divider)

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

    @ViewBuilder
    private var behaviorSectionContent: some View {
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

    @ViewBuilder
    private var webSearchSectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.settings.webSearchProvider == .none,
               SearchGatewayFactory.hasSuggestedGateway(settings: store.settings),
               let gatewayURL = store.settings.searchGatewayURL?.absoluteString {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local gateway detected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(gatewayURL)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)

                    Button {
                        store.settings.webSearchProvider = .custom
                        store.persistSettings()
                    } label: {
                        Label("Use Local Gateway", systemImage: "bolt.horizontal.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(AppTheme.panelRaised.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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

                if store.settings.webSearchProvider == .custom {
                    Text("Custom gateway requests use the Search Gateway URL below.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                } else {
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
                Text(
                    SearchGatewayFactory.hasSuggestedGateway(settings: store.settings)
                    ? "Live search can use the local gateway above, or you can choose an API provider."
                    : "Enable a search provider for real-time info. Keys stay on-device."
                )
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var backendSectionContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search Gateway URL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField("https://…", text: Binding(
                get: { store.settings.searchGatewayURL?.absoluteString ?? "" },
                set: {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.settings.searchGatewayURL = URL(string: trimmed)
                    if !trimmed.isEmpty {
                        store.settings.webSearchProvider = .custom
                    }
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

            Text("Entering a gateway URL automatically switches Web Search to Custom Gateway.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    @ViewBuilder
    private var aboutSectionContent: some View {
        HStack {
            Text("Version")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
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

    @ViewBuilder
    private var developerSectionContent: some View {
        NavigationLink {
            ModelDiagnosticsView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Diagnostics")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Run on-device audit cases and inspect per-model verdicts.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.appBody(14))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .tint(AppTheme.accent)
    }
}
