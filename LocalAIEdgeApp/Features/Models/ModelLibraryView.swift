import SwiftUI

struct ModelLibraryView: View {
    @Environment(AppStateStore.self) private var store
    @State private var searchText = ""
    @State private var downloadService: ModelDownloadService = URLModelDownloadService()
    @State private var activeDownloads: Set<UUID> = []
    @State private var filterVision = false
    @State private var filterThinking = false
    @State private var filterTools = false
    @State private var filterPhoneOnly = false
    @State private var filterMLX = false
    @State private var modelToDelete: InstalledModel? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection
                    latestReleaseSection
                    systemSection

                    if !installedModels.isEmpty {
                        installedSection
                    }

                    featuredFamiliesSection
                    discoverSection

                    if hasActiveQuery {
                        searchResultsSection
                    } else {
                        familyDirectorySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 104)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Models")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .onAppear { store.reconcileInstalledFiles() }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    removeInstalledModel(model)
                    modelToDelete = nil
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Remove \"\(model.catalogItem.displayName)\" (\(model.catalogItem.diskSize)) from this device? You can re-download it later.")
            }
        }
    }

    private var installedModels: [InstalledModel] {
        store.installedModels.filter { $0.installState == .installed || $0.installState == .downloading }
    }

    private var hasActiveQuery: Bool {
        !searchText.isEmpty || filterVision || filterThinking || filterTools || filterPhoneOnly || filterMLX
    }

    private var filteredCatalog: [ModelCatalogItem] {
        store.catalog.filter { item in
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matches = item.displayName.lowercased().contains(query) ||
                    item.family.rawValue.lowercased().contains(query) ||
                    item.family.lab.lowercased().contains(query) ||
                    item.summary.lowercased().contains(query) ||
                    item.parameterSize.lowercased().contains(query)
                if !matches { return false }
            }

            if filterVision && !item.supportsVision { return false }
            if filterThinking && !item.isThinkingModel { return false }
            if filterTools && !item.supportsToolCalling { return false }
            if filterPhoneOnly && !item.recommendedForIPhone { return false }
            if filterMLX && item.runtimeType != .mlx { return false }

            return true
        }
    }

    private var featuredFamilies: [ModelCatalogItem.ModelFamily] {
        let preferred: [ModelCatalogItem.ModelFamily] = [.gemma, .qwen, .lfm, .openELM]
        let available = Set(store.catalog.map(\.family))
        return preferred.filter { available.contains($0) }
    }

    private var latestReleaseModels: [ModelCatalogItem] {
        store.catalog
            .filter(\.isLatestRelease)
            .sorted(by: sortModels)
    }

    private var allFamilies: [ModelCatalogItem.ModelFamily] {
        let preferred: [ModelCatalogItem.ModelFamily] = [.gemma, .qwen, .lfm, .openELM, .phi, .llama, .deepSeek, .mistral, .smolLM, .smolVLM, .stableLM, .tinyLlama, .kokoro]
        let available = Set(store.catalog.map(\.family))
        let ordered = preferred.filter { available.contains($0) }
        let remainder = available.subtracting(preferred).sorted { $0.rawValue < $1.rawValue }
        return ordered + remainder
    }

    private var filteredFamilyGroups: [(family: ModelCatalogItem.ModelFamily, items: [ModelCatalogItem])] {
        allFamilies.compactMap { family in
            let items = filteredCatalog.filter { $0.family == family }
            guard !items.isEmpty else { return nil }
            return (family, items.sorted(by: sortModels))
        }
    }

    private var activeModel: InstalledModel? {
        store.defaultModel
    }

    private var totalInstalledCountLabel: String {
        let modelCount = installedModels.filter { $0.catalogItem.primaryUse == .chat }.count
        let assetCount = installedModels.filter { $0.catalogItem.primaryUse == .voice }.count

        switch (modelCount, assetCount) {
        case let (models, 0):
            return "\(models) local model\(models == 1 ? "" : "s")"
        case let (models, assets):
            return "\(models) model\(models == 1 ? "" : "s") + \(assets) asset\(assets == 1 ? "" : "s")"
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Studio")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Curated local families, newest on-device releases, and honest runtime boundaries.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    metricPill(value: "\(store.catalog.count)", label: "Variants")
                    metricPill(value: "\(latestReleaseModels.count)", label: "Latest")
                }
            }

            HStack(spacing: 10) {
                overviewBadge(icon: "lock.shield.fill", text: "Private by default", color: AppTheme.success)
                overviewBadge(icon: "cpu.fill", text: "GGUF + MLX", color: AppTheme.accent)
                overviewBadge(icon: "arrow.down.circle.fill", text: totalInstalledCountLabel, color: AppTheme.warning)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var latestReleaseSection: some View {
        Group {
            if !latestReleaseModels.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Latest On-Device", subtitle: "Fresh MLX and llama.cpp lanes surfaced as first-class picks for modern phones.")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(latestReleaseModels.prefix(4)) { item in
                                latestReleaseCard(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func latestReleaseCard(_ item: ModelCatalogItem) -> some View {
        let color = AppTheme.labColor(for: item.family)
        let installed = installedModel(for: item)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.runtimeType == .mlx ? "Latest MLX" : "Latest GGUF")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                        .textCase(.uppercase)

                    Text(item.displayName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: item.runtimeType.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .padding(10)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
            }

            Text(item.summary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                compactMeta(text: item.parameterSize, color: AppTheme.textSecondary)
                compactMeta(text: item.contextWindow, color: AppTheme.warning)
                compactMeta(text: item.runtimeType.label, color: color)
            }

            HStack(spacing: 8) {
                if let installed {
                    Button(installed.isDefault ? "Default" : "Use") {
                        store.setDefaultModel(id: item.id)
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(installed.isDefault ? AppTheme.success : AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((installed.isDefault ? AppTheme.success : AppTheme.accent).opacity(0.14))
                    .clipShape(Capsule())
                } else {
                    Button("Install") {
                        if item.runtimeType == .mlx {
                            startMLXInstall(for: item)
                        } else {
                            startInstall(for: item)
                        }
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppTheme.accentGradient))
                }

                Spacer()
            }
        }
        .frame(width: 270, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surfaceGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 0.7)
        )
    }

    private func metricPill(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func overviewBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "System", subtitle: "Default engine, local stack, and the system lane for future Apple-native routing.")

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(systemAccent.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: activeModel == nil ? "sparkles" : activeModelIcon)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(systemAccent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(activeModel?.catalogItem.displayName ?? "No default assistant")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(activeModel?.catalogItem.summary ?? "Install a featured family to create a device-first default model for chat.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    runtimeCapsule(text: activeModel?.catalogItem.runtimeType.label ?? "Choose model", color: systemAccent)
                    runtimeCapsule(text: activeModel?.catalogItem.supportsVision == true ? "Vision ready" : "Text lane", color: activeModel?.catalogItem.supportsVision == true ? AppTheme.capVision : AppTheme.textSecondary)
                    runtimeCapsule(text: activeModel?.catalogItem.supportsToolCalling == true ? "Tool-capable" : "Offline core", color: activeModel?.catalogItem.supportsToolCalling == true ? AppTheme.capTools : AppTheme.success)
                }

                HStack(spacing: 12) {
                    miniSystemCard(
                        title: "Local stack",
                        detail: "Speech, search, and privacy controls wrap around the active model instead of hiding a cloud fallback.",
                        icon: "lock.desktopcomputer",
                        color: AppTheme.success
                    )

                    miniSystemCard(
                        title: "System lane",
                        detail: "This is where a future Apple-native foundation path can plug in. Current builds ship curated GGUF and MLX families only.",
                        icon: "apple.logo",
                        color: AppTheme.labApple
                    )
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    private var systemAccent: Color {
        activeModel.map { AppTheme.labColor(for: $0.catalogItem.family) } ?? AppTheme.accent
    }

    private var activeModelIcon: String {
        activeModel?.catalogItem.family.labIcon ?? "cpu.fill"
    }

    private func runtimeCapsule(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func miniSystemCard(title: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Installed", subtitle: "Fast switching for what already lives on this device.")

            VStack(spacing: 10) {
                ForEach(installedModels.sorted(by: sortInstalledModels)) { model in
                    installedModelCard(model)
                }
            }
        }
    }

    private func installedModelCard(_ model: InstalledModel) -> some View {
        let color = AppTheme.labColor(for: model.catalogItem.family)
        let isVoiceAsset = model.catalogItem.primaryUse == .voice

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: model.catalogItem.family.labIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                    Text(model.catalogItem.displayName)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    compactMeta(text: model.catalogItem.parameterSize, color: AppTheme.textSecondary)
                    compactMeta(text: model.catalogItem.diskSize, color: AppTheme.textSecondary)
                    compactMeta(text: model.catalogItem.runtimeType.label, color: model.catalogItem.runtimeType == .mlx ? .orange : AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if model.installState == .downloading {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.warning)
                    ProgressView(value: model.progress)
                        .frame(width: 68)
                        .tint(AppTheme.warning)
                }
            } else {
                HStack(spacing: 8) {
                    if isVoiceAsset {
                        installedActionPill(title: "Voice Asset", color: .orange)
                    } else {
                        Button(model.isDefault ? "Default" : "Use") {
                            store.setDefaultModel(id: model.catalogItem.id)
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(model.isDefault ? AppTheme.success : AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((model.isDefault ? AppTheme.success : AppTheme.accent).opacity(0.14))
                        .clipShape(Capsule())
                    }

                    Button {
                        modelToDelete = model
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.destructive)
                            .padding(9)
                            .background(AppTheme.destructive.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func compactMeta(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.panelRaised.opacity(0.7))
            .clipShape(Capsule())
    }

    private func installedActionPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var featuredFamiliesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Featured", subtitle: "Primary families surfaced as destinations instead of a flat provider list.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(featuredFamilies, id: \.self) { family in
                        NavigationLink {
                            familyDetailView(for: family)
                        } label: {
                            familyHeroCard(family)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func familyHeroCard(_ family: ModelCatalogItem.ModelFamily) -> some View {
        let color = AppTheme.labColor(for: family)
        let items = items(for: family)
        let installedCount = installedModels.filter { $0.catalogItem.family == family && $0.installState == .installed }.count
        let highlight = familyHighlight(for: family)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: family.labIcon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(color)
                        Text(family.rawValue)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Text(familyHeadline(for: family))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.7))
            }

            if let highlight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spotlight")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                        .textCase(.uppercase)
                    Text(highlight.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(highlight.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(14)
                .background(Color.black.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 8) {
                familyStat(label: "Variants", value: "\(items.count)")
                familyStat(label: "Installed", value: "\(installedCount)")
                familyStat(label: "Runtime", value: familyDominantRuntime(family).label)
            }
        }
        .frame(width: 286, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func familyStat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Discover", subtitle: hasActiveQuery ? "Filtered variants matching the current search lane." : "Search directly or filter into exact runtime capabilities.")
            searchBar
            capabilityFilterBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(searchText.isEmpty ? AppTheme.textTertiary : AppTheme.accent)

            TextField("Search families, variants, or labs", text: $searchText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(AppTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(searchText.isEmpty ? Color.white.opacity(0.06) : AppTheme.accent.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var capabilityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                capToggle(label: "Thinking", icon: "brain", isOn: $filterThinking, color: AppTheme.capThinking)
                capToggle(label: "Vision", icon: "eye.fill", isOn: $filterVision, color: AppTheme.capVision)
                capToggle(label: "Tools", icon: "wrench.and.screwdriver.fill", isOn: $filterTools, color: AppTheme.capTools)
                capToggle(label: "MLX", icon: "apple.logo", isOn: $filterMLX, color: .orange)
                capToggle(label: "iPhone", icon: "iphone", isOn: $filterPhoneOnly, color: AppTheme.success)
            }
            .padding(.vertical, 2)
        }
    }

    private func capToggle(label: String, icon: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? color.opacity(0.14) : AppTheme.panel)
            .foregroundStyle(isOn.wrappedValue ? color : AppTheme.textSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var familyDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Families", subtitle: "A cleaner directory for browsing families before diving into specific sizes or runtimes.")

            VStack(spacing: 12) {
                ForEach(allFamilies, id: \.self) { family in
                    NavigationLink {
                        familyDetailView(for: family)
                    } label: {
                        familyDirectoryCard(family)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func familyDirectoryCard(_ family: ModelCatalogItem.ModelFamily) -> some View {
        let color = AppTheme.labColor(for: family)
        let items = items(for: family)
        let recommended = items.filter(\.recommendedForIPhone).count
        let installed = installedModels.filter { $0.catalogItem.family == family && $0.installState == .installed }.count

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: family.labIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(family.rawValue)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(family.lab)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }

                Text(familyHeadline(for: family))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    compactMeta(text: "\(items.count) variants", color: AppTheme.textSecondary)
                    compactMeta(text: "\(recommended) phone picks", color: AppTheme.success)
                    if installed > 0 {
                        compactMeta(text: "\(installed) installed", color: AppTheme.accent)
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(16)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if filteredCatalog.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No variants match this lane")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Try clearing one or two filters, or search by family name instead of the exact variant.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(18)
                .background(AppTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(filteredFamilyGroups, id: \.family) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: group.family.labIcon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.labColor(for: group.family))
                            Text(group.family.rawValue)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("\(group.items.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.panelRaised.opacity(0.75))
                                .clipShape(Capsule())
                        }

                        VStack(spacing: 10) {
                            ForEach(group.items) { item in
                                modelTile(for: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func familyDetailView(for family: ModelCatalogItem.ModelFamily) -> some View {
        FamilyDetailView(
            family: family,
            items: items(for: family),
            installedModels: installedModels,
            activeDownloads: activeDownloads,
            onInstall: { item in
                if item.runtimeType == .mlx {
                    startMLXInstall(for: item)
                } else {
                    startInstall(for: item)
                }
            },
            onUse: { modelID in
                store.setDefaultModel(id: modelID)
            },
            onDeleteRequest: { installed in
                modelToDelete = installed
                showDeleteConfirmation = installed != nil
            }
        )
    }

    private func modelTile(for item: ModelCatalogItem) -> some View {
        ModelTile(
            item: item,
            installed: installedModel(for: item),
            isDownloading: activeDownloads.contains(item.id),
            onInstall: {
                if item.runtimeType == .mlx {
                    startMLXInstall(for: item)
                } else {
                    startInstall(for: item)
                }
            },
            onUse: {
                store.setDefaultModel(id: item.id)
            },
            onDelete: {
                let installed = installedModel(for: item)
                modelToDelete = installed
                showDeleteConfirmation = installed != nil
            }
        )
    }

    private func installedModel(for item: ModelCatalogItem) -> InstalledModel? {
        store.installedModels.first(where: { $0.catalogItem.id == item.id })
    }

    private func items(for family: ModelCatalogItem.ModelFamily) -> [ModelCatalogItem] {
        store.catalog.filter { $0.family == family }.sorted(by: sortModels)
    }

    private func familyHighlight(for family: ModelCatalogItem.ModelFamily) -> ModelCatalogItem? {
        let familyItems = items(for: family)
        return familyItems.first(where: { installedModel(for: $0)?.isDefault == true })
            ?? familyItems.first(where: \.recommendedForIPhone)
            ?? familyItems.first
    }

    private func familyDominantRuntime(_ family: ModelCatalogItem.ModelFamily) -> ModelCatalogItem.RuntimeType {
        let familyItems = items(for: family)
        let mlxCount = familyItems.filter { $0.runtimeType == .mlx }.count
        let ggufCount = familyItems.count - mlxCount
        return mlxCount >= ggufCount ? .mlx : .gguf
    }

    private func familyHeadline(for family: ModelCatalogItem.ModelFamily) -> String {
        switch family {
        case .gemma:
            return "Balanced private chat with reliable instruction following and a calm default tone."
        case .qwen:
            return "Fast text-first variants with strong reasoning and tool-friendly behavior."
        case .lfm:
            return "Lean Liquid AI models tuned for concise answers and efficient on-device latency."
        case .openELM:
            return "Apple research lineage and the natural landing spot for future system-native routing."
        case .phi:
            return "Small Microsoft models optimized for compact assistant flows."
        case .kokoro:
            return "Voice assets for expressive local speech output on Apple Silicon devices."
        default:
            return "Curated on-device variants grouped by family instead of exposed as a raw provider feed."
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func sortInstalledModels(lhs: InstalledModel, rhs: InstalledModel) -> Bool {
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault && !rhs.isDefault
        }
        if lhs.installState != rhs.installState {
            return lhs.installState == .installed
        }
        return sortModels(lhs.catalogItem, rhs.catalogItem)
    }

    private func sortModels(_ lhs: ModelCatalogItem, _ rhs: ModelCatalogItem) -> Bool {
        if lhs.isLatestRelease != rhs.isLatestRelease {
            return lhs.isLatestRelease && !rhs.isLatestRelease
        }
        if lhs.recommendedForIPhone != rhs.recommendedForIPhone {
            return lhs.recommendedForIPhone && !rhs.recommendedForIPhone
        }
        if lhs.runtimeType != rhs.runtimeType {
            return lhs.runtimeType == .mlx && rhs.runtimeType != .mlx
        }
        return lhs.displayName < rhs.displayName
    }

    private func startMLXInstall(for item: ModelCatalogItem) {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        guard let mlxModelID = item.mlxModelID else {
            store.markInstallFailed(for: item, message: "No MLX model ID configured")
            return
        }
        activeDownloads.insert(item.id)
        store.updateInstallProgress(for: item, progress: 0, state: .downloading, statusMessage: "Downloading MLX model…")

        Task {
            do {
                try await MLXRuntime.shared.preloadModel(mlxModelID, isVision: item.supportsVision) { fraction in
                    Task { @MainActor in
                        store.updateInstallProgress(for: item, progress: fraction, state: .downloading, statusMessage: "Downloading MLX model… \(Int(fraction * 100))%")
                    }
                }
                await MainActor.run {
                    store.markInstallCompleted(for: item, localPath: mlxModelID)
                    activeDownloads.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    store.markInstallFailed(for: item, message: error.localizedDescription)
                    activeDownloads.remove(item.id)
                }
            }
        }
        #else
        store.markInstallFailed(for: item, message: "MLX models require a real device with Apple Silicon.")
        #endif
    }

    private func startInstall(for item: ModelCatalogItem) {
        activeDownloads.insert(item.id)
        store.updateInstallProgress(for: item, progress: 0, state: .downloading, statusMessage: "Connecting to model host")

        Task {
            do {
                let installed = try await downloadService.beginInstall(for: item) { event in
                    Task { @MainActor in
                        switch event.state {
                        case .downloading:
                            store.updateInstallProgress(for: item, progress: event.progress, state: .downloading, statusMessage: event.message)
                        case .installed:
                            if let localPath = event.localPath {
                                store.markInstallCompleted(for: item, localPath: localPath)
                            }
                        case .failed:
                            store.markInstallFailed(for: item, message: event.message ?? "Download failed")
                        case .notInstalled:
                            break
                        }
                    }
                }

                await MainActor.run {
                    store.upsertInstalledModel(installed)
                    activeDownloads.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    store.markInstallFailed(for: item, message: error.localizedDescription)
                    activeDownloads.remove(item.id)
                }
            }
        }
    }

    private func removeInstalledModel(_ model: InstalledModel?) {
        guard let model else { return }

        Task {
            if model.catalogItem.runtimeType == .mlx {
                #if canImport(MLXLLM) && !targetEnvironment(simulator)
                if let mlxModelID = model.catalogItem.mlxModelID {
                    await MLXRuntime.shared.removeModelCache(for: mlxModelID)
                }
                #endif
                await MainActor.run {
                    store.removeInstalledModel(model.catalogItem)
                }
            } else {
                do {
                    try await downloadService.removeInstall(for: model)
                    await MainActor.run {
                        store.removeInstalledModel(model.catalogItem)
                    }
                } catch {
                    await MainActor.run {
                        store.markInstallFailed(for: model.catalogItem, message: error.localizedDescription)
                    }
                }
            }
        }
    }
}

private struct FamilyDetailView: View {
    let family: ModelCatalogItem.ModelFamily
    let items: [ModelCatalogItem]
    let installedModels: [InstalledModel]
    let activeDownloads: Set<UUID>
    let onInstall: (ModelCatalogItem) -> Void
    let onUse: (UUID) -> Void
    let onDeleteRequest: (InstalledModel?) -> Void

    private var color: Color {
        AppTheme.labColor(for: family)
    }

    private var spotlight: ModelCatalogItem? {
        items.first(where: { installedModel(for: $0)?.isDefault == true })
            ?? items.first(where: \.recommendedForIPhone)
            ?? items.first
    }

    private var installedCount: Int {
        items.filter { installedModel(for: $0)?.installState == .installed }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if let spotlight {
                    spotlightCard(spotlight)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Variants")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(items) { item in
                        ModelTile(
                            item: item,
                            installed: installedModel(for: item),
                            isDownloading: activeDownloads.contains(item.id),
                            onInstall: { onInstall(item) },
                            onUse: { onUse(item.id) },
                            onDelete: { onDeleteRequest(installedModel(for: item)) }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(family.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: family.labIcon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color)
                        Text(family.lab)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                    }

                    Text(familyTitle)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(familyDescription)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    heroMetric(value: "\(items.count)", label: "Variants")
                    heroMetric(value: "\(installedCount)", label: "Installed")
                }
            }

            HStack(spacing: 8) {
                detailBadge(text: dominantRuntimeLabel, color: dominantRuntimeColor)
                detailBadge(text: phoneReadyLabel, color: AppTheme.success)
                detailBadge(text: familyCapabilityLabel, color: familyCapabilityColor)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func spotlightCard(_ item: ModelCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spotlight variant")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)

            Text(item.displayName)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text(item.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                detailBadge(text: item.parameterSize, color: AppTheme.textSecondary)
                detailBadge(text: item.diskSize, color: AppTheme.textSecondary)
                detailBadge(text: item.runtimeType.label, color: item.runtimeType == .mlx ? .orange : AppTheme.accent)
            }
        }
        .padding(18)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func installedModel(for item: ModelCatalogItem) -> InstalledModel? {
        installedModels.first(where: { $0.catalogItem.id == item.id })
    }

    private var familyTitle: String {
        switch family {
        case .gemma:
            return "Gemma on device"
        case .qwen:
            return "Qwen text lineup"
        case .lfm:
            return "Liquid AI compact stack"
        case .openELM:
            return "Apple research lane"
        default:
            return "\(family.rawValue) family"
        }
    }

    private var familyDescription: String {
        switch family {
        case .gemma:
            return "A grounded family for device-first chat. In this app, Gemma 4 currently rides the llama.cpp GGUF lane for dependable local text generation."
        case .qwen:
            return "Reasoning-oriented text models with a fast MLX path. This build intentionally surfaces supported Qwen 3 variants instead of unsupported 3.5 entries."
        case .lfm:
            return "Liquid AI variants focused on small-footprint local execution. The current catalog favors text models that match the shipped runtime support."
        case .openELM:
            return "Apple's research family and the most natural place to anchor a future system-model route, while today's app remains centered on downloadable local models."
        case .kokoro:
            return "Local voice assets for speech output. These complement chat families rather than replacing them as the default conversational engine."
        default:
            return "Browse the supported variants in this family, compare runtimes, and set a default once the model is installed on-device."
        }
    }

    private var dominantRuntimeLabel: String {
        let mlxCount = items.filter { $0.runtimeType == .mlx }.count
        return mlxCount >= (items.count - mlxCount) ? "MLX-first" : "GGUF-first"
    }

    private var dominantRuntimeColor: Color {
        dominantRuntimeLabel == "MLX-first" ? .orange : AppTheme.accent
    }

    private var phoneReadyLabel: String {
        let count = items.filter(\.recommendedForIPhone).count
        return count == 0 ? "Selective fit" : "\(count) phone picks"
    }

    private var familyCapabilityLabel: String {
        if items.contains(where: \.supportsVision) {
            return "Vision lane"
        }
        if items.contains(where: \.supportsToolCalling) {
            return "Tools lane"
        }
        if items.contains(where: \.isThinkingModel) {
            return "Thinking lane"
        }
        return "Text lane"
    }

    private var familyCapabilityColor: Color {
        if items.contains(where: \.supportsVision) {
            return AppTheme.capVision
        }
        if items.contains(where: \.supportsToolCalling) {
            return AppTheme.capTools
        }
        if items.contains(where: \.isThinkingModel) {
            return AppTheme.capThinking
        }
        return AppTheme.textSecondary
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.panel.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ModelTile: View {
    let item: ModelCatalogItem
    let installed: InstalledModel?
    let isDownloading: Bool
    let onInstall: () -> Void
    let onUse: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    private var labColor: Color {
        AppTheme.labColor(for: item.family)
    }

    private var isInstalled: Bool {
        installed?.installState == .installed
    }

    private var isActiveDownload: Bool {
        isDownloading || installed?.installState == .downloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.displayName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                        statusBadge
                    }

                    HStack(spacing: 6) {
                        tileMeta(text: item.family.lab, color: labColor)
                        tileMeta(text: item.runtimeType.label, color: item.runtimeType == .mlx ? .orange : AppTheme.textSecondary)
                        tileMeta(text: item.parameterSize, color: AppTheme.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(10)
                        .background(AppTheme.panelRaised.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                specCell(icon: "scalemass.fill", value: item.parameterSize, label: "Params")
                specDivider
                specCell(icon: "text.alignleft", value: item.contextWindow, label: "Context")
                specDivider
                specCell(icon: "internaldrive.fill", value: item.diskSize, label: "Size")
                specDivider
                specCell(icon: item.runtimeType.icon, value: item.runtimeType.label, label: "Runtime")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(AppTheme.panelRaised.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            capabilityRow

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    inputCategories

                    if let message = installed?.statusMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.destructive)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            actionRow
        }
        .padding(16)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var statusBadge: some View {
        Group {
            if installed?.installState == .installed {
                smallStatus(text: installed?.isDefault == true ? "Default" : "Installed", color: installed?.isDefault == true ? AppTheme.success : labColor)
            } else if isActiveDownload {
                smallStatus(text: "\(Int((installed?.progress ?? 0) * 100))%", color: AppTheme.warning)
            } else if installed?.installState == .failed {
                smallStatus(text: "Failed", color: AppTheme.destructive)
            }
        }
    }

    private func smallStatus(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func tileMeta(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.panelRaised.opacity(0.75))
            .clipShape(Capsule())
    }

    private func specCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var specDivider: some View {
        Rectangle()
            .fill(AppTheme.hairline)
            .frame(width: 1, height: 30)
    }

    private var capabilityRow: some View {
        HStack(spacing: 6) {
            ForEach(item.capabilities, id: \.self) { capability in
                let color = AppTheme.capabilityColor(for: capability)
                HStack(spacing: 4) {
                    Image(systemName: capability.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(capability.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            }

            if item.recommendedForIPhone {
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9, weight: .bold))
                    Text("iPhone")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.success.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private var inputCategories: some View {
        VStack(alignment: .leading, spacing: 6) {
            inputLine(prefix: item.inputCategoriesDifferByRuntime ? "Input (Source)" : "Input", categories: item.sourceInputCategories, tint: AppTheme.textSecondary)

            if item.inputCategoriesDifferByRuntime {
                inputLine(prefix: "Input (App)", categories: item.runtimeInputCategories, tint: AppTheme.accent)
            }
        }
    }

    private func inputLine(prefix: String, categories: [ModelCatalogItem.InputCategory], tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(categories, id: \.self) { category in
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(category.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if isInstalled {
                if item.primaryUse == .voice {
                    Text("Voice asset ready")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Button(action: onUse) {
                        Text(installed?.isDefault == true ? "Default model" : "Use for chat")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(installed?.isDefault == true ? AppTheme.success : AppTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background((installed?.isDefault == true ? AppTheme.success : AppTheme.accent).opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.destructive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppTheme.destructive.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if isActiveDownload {
                HStack(spacing: 8) {
                    ProgressView(value: installed?.progress ?? 0)
                        .tint(AppTheme.warning)
                    Text("Downloading")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.warning)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppTheme.panelRaised.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button(action: onInstall) {
                    HStack(spacing: 6) {
                        Image(systemName: item.runtimeType == .mlx ? "apple.logo" : "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(item.primaryUse == .voice ? "Download voice asset" : item.runtimeType == .mlx ? "Download MLX model" : "Download model")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(item.runtimeType == .mlx ? .orange : AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background((item.runtimeType == .mlx ? Color.orange : AppTheme.accent).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item.runtimeType == .gguf && item.downloadURL == nil)
            }
        }
    }
}
