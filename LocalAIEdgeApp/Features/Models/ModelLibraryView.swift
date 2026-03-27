import SwiftUI

struct ModelLibraryView: View {
    @Environment(AppStateStore.self) private var store
    @State private var searchText = ""
    @State private var downloadService: ModelDownloadService = URLModelDownloadService()
    @State private var activeDownloads: Set<UUID> = []
    @State private var selectedLab: String? = nil
    @State private var filterVision = false
    @State private var filterThinking = false
    @State private var filterTools = false
    @State private var filterPhoneOnly = false
    @State private var filterMLX = false
    @State private var expandedModelID: UUID? = nil
    @State private var modelToDelete: InstalledModel? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    searchBar
                    labFilterBar
                    capabilityFilterBar
                    statsBar

                    if !installedModels.isEmpty {
                        installedSection
                    }

                    catalogSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 90)
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

    // MARK: - Computed Properties

    private var installedModels: [InstalledModel] {
        store.installedModels.filter { $0.installState == .installed || $0.installState == .downloading }
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
            if let lab = selectedLab, item.family.lab != lab { return false }
            if filterVision && !item.supportsVision { return false }
            if filterThinking && !item.isThinkingModel { return false }
            if filterTools && !item.supportsToolCalling { return false }
            if filterPhoneOnly && !item.recommendedForIPhone { return false }
            if filterMLX && item.runtimeType != .mlx { return false }
            return true
        }
    }

    private var groupedByLab: [(lab: String, items: [ModelCatalogItem])] {
        var grouped: [String: [ModelCatalogItem]] = [:]
        for item in filteredCatalog {
            grouped[item.family.lab, default: []].append(item)
        }
        let labOrder = MockCatalogData.allLabs
        return labOrder.compactMap { lab in
            guard let items = grouped[lab], !items.isEmpty else { return nil }
            return (lab: lab, items: items)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(searchText.isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                .animation(.easeOut(duration: 0.2), value: searchText.isEmpty)

            TextField("Search models, labs…", text: $searchText)
                .font(.system(size: 15))
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
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.panelRaised.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    searchText.isEmpty ? AppTheme.hairline : AppTheme.accent.opacity(0.35),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.2), value: searchText.isEmpty)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text("Edge AI Models")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text("\(store.catalog.count) chat models and voice assets from \(MockCatalogData.allLabs.count) labs — llama.cpp + MLX runtimes")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Lab Filter Bar

    private var labFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                labChip(label: "All Labs", lab: nil, icon: "square.grid.2x2.fill", color: AppTheme.accent)

                ForEach(MockCatalogData.allLabs, id: \.self) { lab in
                    let family = store.catalog.first(where: { $0.family.lab == lab })?.family
                    labChip(
                        label: lab,
                        lab: lab,
                        icon: family?.labIcon ?? "questionmark.circle",
                        color: family.map { AppTheme.labColor(for: $0) } ?? AppTheme.accent
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func labChip(label: String, lab: String?, icon: String, color: Color) -> some View {
        let isSelected = selectedLab == lab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLab = lab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.25) : AppTheme.panelRaised.opacity(0.6))
            .foregroundStyle(isSelected ? color : AppTheme.textSecondary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Capability Filters

    private var capabilityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                capToggle(label: "Thinking", icon: "brain", isOn: $filterThinking, color: AppTheme.capThinking)
                capToggle(label: "Vision", icon: "eye.fill", isOn: $filterVision, color: AppTheme.capVision)
                capToggle(label: "Tool Call", icon: "wrench.and.screwdriver.fill", isOn: $filterTools, color: AppTheme.capTools)
                capToggle(label: "MLX", icon: "apple.logo", isOn: $filterMLX, color: .orange)
                capToggle(label: "iPhone", icon: "iphone", isOn: $filterPhoneOnly, color: AppTheme.success)
            }
        }
    }

    private func capToggle(label: String, icon: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn.wrappedValue ? color.opacity(0.2) : AppTheme.panel)
            .foregroundStyle(isOn.wrappedValue ? color : AppTheme.textSecondary)
            .overlay(
                Capsule()
                    .stroke(isOn.wrappedValue ? color.opacity(0.5) : AppTheme.hairline, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statBadge(count: filteredCatalog.count, icon: "cube.fill", color: AppTheme.accent)
                statBadge(count: filteredCatalog.filter { $0.runtimeType == .mlx }.count, icon: "apple.logo", color: .orange)
                statBadge(count: filteredCatalog.filter(\.isThinkingModel).count, icon: "brain", color: AppTheme.capThinking)
                statBadge(count: filteredCatalog.filter(\.supportsVision).count, icon: "eye.fill", color: AppTheme.capVision)
                statBadge(count: filteredCatalog.filter(\.supportsToolCalling).count, icon: "wrench.fill", color: AppTheme.capTools)
            }
            .padding(.vertical, 2)
        }
    }

    private func statBadge(count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Installed Section

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                Text("Installed")
                    .font(.headline.weight(.bold))
                Text("(\(installedModels.count))")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ForEach(installedModels) { model in
                installedModelCard(model)
            }
        }
    }

    private func installedModelCard(_ model: InstalledModel) -> some View {
        let labColor = AppTheme.labColor(for: model.catalogItem.family)
        let isVoiceAsset = model.catalogItem.primaryUse == .voice

        return HStack(spacing: 12) {
            // Lab accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(labColor)
                .frame(width: 4, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.catalogItem.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(model.catalogItem.parameterSize)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                    Text("•")
                    Text(model.catalogItem.contextWindow + " ctx")
                        .font(.caption2.monospacedDigit())
                    Text("•")
                    Text(model.catalogItem.diskSize)
                        .font(.caption2.monospacedDigit())
                    Text("•")
                    HStack(spacing: 2) {
                        Image(systemName: model.catalogItem.runtimeType.icon)
                            .font(.system(size: 8))
                        Text(model.catalogItem.runtimeType.label)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(model.catalogItem.runtimeType == .mlx ? .orange : AppTheme.textSecondary)
                }
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if model.installState == .downloading {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(model.progress * 100))%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.warning)
                    ProgressView(value: model.progress)
                        .frame(width: 60)
                        .tint(AppTheme.warning)
                }
            } else {
                HStack(spacing: 8) {
                    if isVoiceAsset {
                        Text("Voice Asset")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    } else {
                        Button(model.isDefault ? "Default" : "Use") {
                            store.setDefaultModel(id: model.catalogItem.id)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(model.isDefault ? AppTheme.success.opacity(0.2) : AppTheme.accent.opacity(0.15))
                        .foregroundStyle(model.isDefault ? AppTheme.success : AppTheme.accent)
                        .clipShape(Capsule())
                    }

                    Button {
                        modelToDelete = model
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.7))
                            .padding(7)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.panel.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(model.isDefault ? AppTheme.success.opacity(0.3) : AppTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Catalog Section

    private var catalogSection: some View {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
            ForEach(groupedByLab, id: \.lab) { group in
                Section {
                    ForEach(group.items) { item in
                        modelCard(item)
                    }
                } header: {
                    labSectionHeader(group.lab, count: group.items.count)
                }
            }
        }
    }

    private func labSectionHeader(_ lab: String, count: Int) -> some View {
        let family = store.catalog.first(where: { $0.family.lab == lab })?.family
        let color = family.map { AppTheme.labColor(for: $0) } ?? AppTheme.accent

        return HStack(spacing: 8) {
            Image(systemName: family?.labIcon ?? "building.2.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(lab)
                .font(.headline.weight(.heavy))
                .foregroundStyle(AppTheme.textPrimary)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(AppTheme.background)
    }

    // MARK: - Model Card

    private func modelCard(_ item: ModelCatalogItem) -> some View {
        let installed = store.installedModels.first(where: { $0.catalogItem.id == item.id })
        let labColor = AppTheme.labColor(for: item.family)
        let isExpanded = expandedModelID == item.id

        return VStack(alignment: .leading, spacing: 0) {
            // Top: Lab accent line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [labColor, labColor.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Name + Status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)

                        HStack(spacing: 6) {
                            Text(item.family.lab)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(labColor)

                            // Runtime badge
                            HStack(spacing: 3) {
                                Image(systemName: item.runtimeType.icon)
                                    .font(.system(size: 8, weight: .bold))
                                Text(item.runtimeType.label)
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.runtimeType == .mlx ? Color.orange.opacity(0.15) : AppTheme.panelRaised)
                            .foregroundStyle(item.runtimeType == .mlx ? .orange : AppTheme.textSecondary)
                            .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    statusBadge(for: installed)
                }

                // Row 2: Specs row
                specsRow(item)

                // Row 3: Capability badges
                if !item.capabilities.isEmpty {
                    capabilityBadges(item)
                }

                // Row 4: Summary (expandable)
                if isExpanded {
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Row 5: Error message
                if let msg = installed?.statusMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(2)
                }

                // Row 6: Action buttons
                actionRow(for: item, installed: installed)
            }
            .padding(14)
        }
        .background(AppTheme.panel.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    installed?.installState == .installed
                        ? AppTheme.success.opacity(0.3)
                        : AppTheme.hairline,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedModelID = isExpanded ? nil : item.id
            }
        }
    }

    // MARK: - Specs Row

    private func specsRow(_ item: ModelCatalogItem) -> some View {
        HStack(spacing: 0) {
            specCell(icon: "scalemass.fill", value: item.parameterSize, label: "Params")
            specDivider
            specCell(icon: "text.alignleft", value: item.contextWindow, label: "Context")
            specDivider
            specCell(icon: "internaldrive.fill", value: item.diskSize, label: "Size")
            specDivider
            specCell(icon: "memorychip.fill", value: item.quantization.replacingOccurrences(of: "GGUF ", with: ""), label: "Quant")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(AppTheme.panelRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func specCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var specDivider: some View {
        Rectangle()
            .fill(AppTheme.hairline)
            .frame(width: 1, height: 28)
    }

    // MARK: - Capability Badges

    private func capabilityBadges(_ item: ModelCatalogItem) -> some View {
        HStack(spacing: 6) {
            ForEach(item.capabilities, id: \.self) { cap in
                let color = AppTheme.capabilityColor(for: cap)
                HStack(spacing: 4) {
                    Image(systemName: cap.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(cap.rawValue)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 0.5)
                )
                .clipShape(Capsule())
            }

            if item.recommendedForIPhone {
                HStack(spacing: 3) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9, weight: .bold))
                    Text("iPhone")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.success.opacity(0.12))
                .foregroundStyle(AppTheme.success)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Status Badge

    private func statusBadge(for installed: InstalledModel?) -> some View {
        Group {
            switch installed?.installState {
            case .installed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Installed")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.success.opacity(0.15))
                .foregroundStyle(AppTheme.success)
                .clipShape(Capsule())

            case .downloading:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("\(Int((installed?.progress ?? 0) * 100))%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.warning.opacity(0.15))
                .foregroundStyle(AppTheme.warning)
                .clipShape(Capsule())

            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Failed")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Action Row

    private func actionRow(for item: ModelCatalogItem, installed: InstalledModel?) -> some View {
        HStack(spacing: 8) {
            if installed?.installState == .installed {
                if item.primaryUse == .voice {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 11))
                        Text("Voice Asset Ready")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Button {
                        store.setDefaultModel(id: item.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: installed?.isDefault == true ? "star.fill" : "message.fill")
                                .font(.system(size: 11))
                            Text(installed?.isDefault == true ? "Default" : "Use for Chat")
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(installed?.isDefault == true ? AppTheme.success.opacity(0.2) : AppTheme.accent.opacity(0.15))
                        .foregroundStyle(installed?.isDefault == true ? AppTheme.success : AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Button {
                    modelToDelete = installed
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(9)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            } else if installed?.installState == .downloading || activeDownloads.contains(item.id) {
                HStack(spacing: 8) {
                    ProgressView(value: installed?.progress ?? 0)
                        .tint(AppTheme.warning)
                    Text("Downloading…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(AppTheme.panelRaised.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            } else {
                if item.runtimeType == .mlx {
                    // MLX models: download via MLXLLM with progress tracking
                    Button {
                        startMLXInstall(for: item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 12))
                            Text(item.primaryUse == .voice ? "Download Voice Asset" : "Download MLX Model")
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    Button {
                        startInstall(for: item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: installed?.installState == .failed ? "arrow.clockwise" : "arrow.down.circle.fill")
                                .font(.system(size: 12))
                            Text(installed?.installState == .failed ? "Retry" : "Download")
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(item.downloadURL != nil ? AppTheme.accent.opacity(0.15) : AppTheme.panelRaised.opacity(0.3))
                        .foregroundStyle(item.downloadURL != nil ? AppTheme.accent : AppTheme.textSecondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(item.downloadURL == nil)
                }
            }
        }
    }

    // MARK: - Actions

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

    private func reconcileInstalledFiles() {
        store.reconcileInstalledFiles()
    }
}
