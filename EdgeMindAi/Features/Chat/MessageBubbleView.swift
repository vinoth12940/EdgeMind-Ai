import SwiftUI
import ImageIO

struct MessageBubbleView: View {
    let message: ChatMessage
    var isGenerating: Bool = false

    @State private var thinkingExpanded = false
    @State private var searchExpanded = false
    @State private var previewItem: AttachmentPreviewItem?

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isRecoveryMessage: Bool { AssistantResponseFallback.isEmptyOutputMessage(message.text) }

    @ViewBuilder
    var body: some View {
        switch message.role {
        case .system:
            if !isTransientToolStatus {
                systemNotice
            }
        case .user:
            userRow
        case .assistant:
            assistantRow
        }
    }

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: 2) {
            VStack(alignment: .leading, spacing: 6) {
                if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                    Button {
                        previewItem = .image(data: imageData, title: "Image")
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                previewBadge
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview image attachment")
                }

                if !documentAttachments.isEmpty {
                    attachmentChips
                }

                MarkdownTextView(text: message.text, isUser: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.userBubbleGradient)
            )

            messageTimestamp
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 42)
        .sheet(item: $previewItem) { item in
            AttachmentPreviewSheet(item: item)
        }
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 9) {
                if hasWorkflowActivity {
                    WorkflowCard(
                        citations: message.citations,
                        toolActivities: message.toolActivities,
                        thinkingContent: message.thinkingContent,
                        thinkingDuration: message.thinkingDurationSeconds,
                        generationDuration: message.generationDurationSeconds,
                        isGenerating: isGenerating
                    )
                    .padding(.bottom, 1)
                }

                if let imageData = message.imageData, let uiImage = previewImage(from: imageData) {
                    Button {
                        previewItem = .image(data: imageData, title: "Image")
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                previewBadge
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview image attachment")
                    .padding(.top, 4)
                }

                if !documentAttachments.isEmpty {
                    attachmentChips
                        .padding(.top, 4)
                }

                // Render completed local tools
                let localTools = completedLocalTools
                ForEach(localTools) { activity in
                    LocalToolResultCard(
                        toolName: activity.name,
                        output: activity.output,
                        attachments: message.attachments,
                        duration: activity.duration
                    )
                    .padding(.vertical, 4)
                }

                if isRecoveryMessage {
                    recoveryCard
                        .padding(.vertical, 8)
                } else if !message.text.isEmpty && !isTransientToolStatus {
                    MarkdownTextView(text: message.text, isUser: false, citations: message.citations)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                } else if hasActivitySummary && message.text.isEmpty && localTools.isEmpty {
                    AssistantWorkingPlaceholder()
                }

                if !message.citations.isEmpty {
                    SearchCitationsFooter(citations: message.citations)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.panelRaised.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardStroke.opacity(0.78), lineWidth: 0.6)
            )

            messageTimestamp
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
        .padding(.vertical, 4)
        .sheet(item: $previewItem) { item in
            AttachmentPreviewSheet(item: item)
        }
    }

    private var hasActivitySummary: Bool {
        !message.citations.isEmpty
            || !message.toolActivities.isEmpty
            || message.thinkingContent != nil
    }

    private var hasWorkflowActivity: Bool {
        message.thinkingContent != nil
            || !message.citations.isEmpty
            || message.toolActivities.contains { $0.name.lowercased() == "web_search" }
    }

    private var completedLocalTools: [ChatToolActivity] {
        message.toolActivities.filter {
            $0.status == .completed && Self.isStructuredLocalTool($0.name)
        }
    }

    private var isTransientToolStatus: Bool {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("🔍 Searching:")
            || trimmed == "🔍 Searching the web…"
            || trimmed == "🧮 Calculating…"
            || trimmed == "🕒 Reading current time…"
            || trimmed == "📱 Reading device info…"
            || trimmed == "🔋 Reading battery level…"
            || trimmed == "💬 Searching chats…"
            || trimmed == "📄 Reading document…"
            || trimmed.hasPrefix("🔄 Retrying")
    }

    private static func isStructuredLocalTool(_ name: String) -> Bool {
        switch name.lowercased() {
        case "calculate", "get_current_time", "get_device_info", "get_battery_level", "search_chats", "read_document":
            return true
        default:
            return false
        }
    }

    private var documentAttachments: [ChatAttachment] {
        message.attachments.filter { $0.kind != .image }
    }

    private var attachmentChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(documentAttachments) { attachment in
                Button {
                    previewItem = .document(attachment)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: attachment.kind))
                            .font(.system(size: 10, weight: .bold))
                        Text(attachment.fileName)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle((isUser ? Color.white : AppTheme.textSecondary).opacity(0.62))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isUser ? Color.white.opacity(0.92) : AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isUser ? Color.white.opacity(0.16) : AppTheme.subtleFill)
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(attachment.fileName)")
            }
        }
    }

    private var previewBadge: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black.opacity(0.54)))
    }

    private func icon(for kind: ChatAttachment.Kind) -> String {
        switch kind {
        case .image: return "photo"
        case .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .markdown: return "text.alignleft"
        }
    }

    private var systemNotice: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(message.text)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.panelRaised.opacity(0.82))
            .clipShape(Capsule())
            Spacer(minLength: 0)
        }
    }

    private var recoveryCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.warning)
            Text("No visible answer. Try a shorter prompt, switch models, or keep search enabled for live questions.")
                .font(.appBody(13))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var messageTimestamp: some View {
        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.appBody(10))
            .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
            .padding(.horizontal, 4)
    }

    private func previewImage(from data: Data) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let fileName: String
    let kindLabel: String
    let mimeType: String
    let image: UIImage?
    let extractedText: String?
    let rawByteCount: Int?

    static func image(data: Data, title: String) -> AttachmentPreviewItem {
        AttachmentPreviewItem(
            title: title,
            fileName: title,
            kindLabel: "Image",
            mimeType: "image/jpeg",
            image: UIImage(data: data),
            extractedText: nil,
            rawByteCount: data.count
        )
    }

    static func image(_ image: UIImage, title: String) -> AttachmentPreviewItem {
        AttachmentPreviewItem(
            title: title,
            fileName: title,
            kindLabel: "Image",
            mimeType: "image/jpeg",
            image: image,
            extractedText: nil,
            rawByteCount: image.jpegData(compressionQuality: 0.9)?.count
        )
    }

    static func document(_ attachment: ChatAttachment) -> AttachmentPreviewItem {
        AttachmentPreviewItem(
            title: attachment.fileName,
            fileName: attachment.fileName,
            kindLabel: attachment.displayLabel,
            mimeType: attachment.mimeType,
            image: nil,
            extractedText: attachment.extractedText,
            rawByteCount: attachment.rawData?.count
        )
    }
}

struct AttachmentPreviewSheet: View {
    let item: AttachmentPreviewItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = item.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.surfaceStroke, lineWidth: 0.8)
                                )
                    } else {
                        documentMetadata

                        if let text = item.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            Text(text)
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundStyle(AppTheme.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(AppTheme.panelRaised.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            unavailableDocumentPreview
                        }
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var documentMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(item.fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
            }

            FlowLayout(spacing: 8) {
                previewMetaPill(item.kindLabel)
                previewMetaPill(item.mimeType)
                if let rawByteCount = item.rawByteCount {
                    previewMetaPill(ByteCountFormatter.string(fromByteCount: Int64(rawByteCount), countStyle: .file))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelRaised.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var unavailableDocumentPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            Text("No preview text is available for this attachment.")
                .font(.appBody(14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.panelRaised.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func previewMetaPill(_ value: String) -> some View {
        Text(value)
            .font(.appCaps(10))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.subtleFill)
            .clipShape(Capsule())
    }
}

// MARK: - Workflow & Timeline Components

struct WorkflowCard: View {
    let citations: [SearchCitation]
    let toolActivities: [ChatToolActivity]
    let thinkingContent: String?
    let thinkingDuration: Int?
    let generationDuration: Double?
    let isGenerating: Bool

    @State private var isCollapsed = true
    @State private var hasInitializedState = false
    @State private var thinkingExpanded = false
    @State private var sourcesExpanded = false

    private let workflowColor = Color(red: 0.12, green: 0.53, blue: 0.53)
    private let tint = AppTheme.accent
    private let searchColor = Color(red: 0.18, green: 0.78, blue: 0.72)
    private let thinkingColor = AppTheme.capThinking

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCollapsed {
                collapsedPill
            } else {
                expandedCard
            }
        }
        .onAppear {
            if !hasInitializedState {
                // Collapse automatically if the answer is already complete
                isCollapsed = (thinkingDuration != nil || thinkingContent == nil) && (generationDuration != nil || toolActivities.isEmpty)
                hasInitializedState = true
            }
        }
    }

    private var collapsedPill: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isCollapsed = false
            }
        } label: {
            HStack(spacing: 6) {
                // Circle brain icon on the far left
                ZStack {
                    Circle()
                        .stroke(workflowColor.opacity(0.24), lineWidth: 1)
                        .background(Circle().fill(workflowColor.opacity(0.06)))
                        .frame(width: 22, height: 22)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundStyle(workflowColor)
                }

                if hasSearch {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(workflowColor)

                    Text("Searched web")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    if !citations.isEmpty {
                        Text("•")
                            .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                        Text("\(citations.count) sources")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                } else if let tool = primaryLocalTool {
                    Image(systemName: localToolIcon(tool.name))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(workflowColor)

                    Text(tool.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                if thinkingContent != nil {
                    Text("•")
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(workflowColor)

                    Text(thinkingDurationText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppTheme.panelRaised))
            .overlay(
                Capsule().stroke(AppTheme.cardStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCollapsed = true
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(workflowColor.opacity(0.24), lineWidth: 1)
                            .background(Circle().fill(workflowColor.opacity(0.06)))
                            .frame(width: 32, height: 32)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundStyle(workflowColor)
                    }

                    Text("Working on your question")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            // Steps Timeline
            VStack(alignment: .leading, spacing: 0) {
                // Step 1: Thinking
                if thinkingContent != nil || thinkingDuration != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                thinkingExpanded.toggle()
                            }
                        } label: {
                            TimelineRow(
                                isFirst: true,
                                isLast: !hasSearch && generationDuration == nil,
                                isActive: thinkingDuration == nil,
                                icon: "brain.head.profile",
                                tint: workflowColor
                            ) {
                                HStack {
                                    Text(thinkingDuration == nil ? "Thinking" : "Thought")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.textPrimary)

                                    if thinkingDuration == nil {
                                        ThinkingDotsView()
                                    }

                                    Spacer()

                                    Text(thinkingDurationText)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(workflowColor.opacity(0.7))
                                        .rotationEffect(.degrees(thinkingExpanded ? 90 : 0))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        if thinkingExpanded, let content = thinkingContent {
                            ThinkingDetailCard(
                                thinkingContent: content,
                                isStreaming: thinkingDuration == nil,
                                tint: workflowColor
                            )
                            .padding(.leading, 42)
                            .padding(.bottom, 8)
                        }
                    }
                }

                // Step 2: Searching web (only if search was executed)
                if hasSearch {
                    let searchActivity = toolActivities.first(where: { $0.name.lowercased() == "web_search" })
                    let isSearchActive = searchActivity?.status == .running

                    TimelineRow(
                        isFirst: thinkingContent == nil,
                        isLast: citations.isEmpty && generationDuration == nil,
                        isActive: isSearchActive,
                        icon: "globe",
                        tint: workflowColor
                    ) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isSearchActive ? "Searching web" : "Searched web")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)

                                if let query = searchQuery {
                                    Text(query)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }

                            Spacer()

                            Text(searchDurationText(searchActivity))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    // Step 3: Found sources
                    if !citations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    sourcesExpanded.toggle()
                                }
                            } label: {
                                TimelineRow(
                                    isFirst: false,
                                    isLast: generationDuration == nil,
                                    isActive: false,
                                    icon: "checkmark",
                                    tint: workflowColor
                                ) {
                                    HStack {
                                        Text("Found \(citations.count) sources")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppTheme.textPrimary)

                                        Spacer()

                                        Text("1s")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppTheme.textSecondary)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(workflowColor.opacity(0.7))
                                            .rotationEffect(.degrees(sourcesExpanded ? 90 : 0))
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if sourcesExpanded {
                                CompactSourcesList(citations: citations)
                                    .padding(.leading, 42)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                }

                // Step 4: Reading sources / answering
                if hasSearch || thinkingContent != nil {
                    let isReadingActive = isGenerating && generationDuration == nil
                    TimelineRow(
                        isFirst: thinkingContent == nil && !hasSearch,
                        isLast: true,
                        isActive: isReadingActive,
                        icon: "brain.head.profile",
                        tint: workflowColor
                    ) {
                        HStack {
                            Text(isReadingActive ? "Reading sources" : "Answer generated")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)

                            if isReadingActive {
                                ThinkingDotsView()
                            }

                            Spacer()

                            Text(generationDurationText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.panelRaised.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 0.5)
        )
    }

    private var hasSearch: Bool {
        toolActivities.contains { $0.name.lowercased() == "web_search" } || !citations.isEmpty
    }

    private var primaryLocalTool: ChatToolActivity? {
        toolActivities.first { $0.name.lowercased() != "web_search" }
    }

    private var thinkingDurationText: String {
        guard let dur = thinkingDuration else { return "2s" }
        return "Thought \(dur)s"
    }

    private func searchDurationText(_ activity: ChatToolActivity?) -> String {
        guard let activity, let dur = activity.duration else { return "4s" }
        return String(format: "%.1fs", dur)
    }

    private var generationDurationText: String {
        guard let dur = generationDuration else { return "3s" }
        return String(format: "%.1fs", dur)
    }

    private var searchQuery: String? {
        if let activity = toolActivities.first(where: { $0.name.lowercased() == "web_search" }) {
            return WebSearchTool.extractQuery(activity.output) ?? WebSearchTool.extractQuery(activity.displayName)
        }
        return nil
    }

    private func localToolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "calculate": return "function"
        case "get_current_time": return "clock"
        case "get_device_info": return "iphone"
        case "get_battery_level": return "battery.100percent"
        case "search_chats": return "message.badge.filled.and.checkmark"
        case "read_document": return "doc.text"
        default: return "checkmark.circle"
        }
    }
}

struct TimelineRow<Content: View>: View {
    let isFirst: Bool
    let isLast: Bool
    let isActive: Bool
    let icon: String
    let tint: Color
    let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Column 1: Timeline Circle Icon & Connector Lines
            VStack(spacing: 0) {
                if isFirst {
                    Spacer().frame(height: 6)
                } else {
                    Rectangle()
                        .fill(tint.opacity(0.25))
                        .frame(width: 1.5, height: 10)
                }

                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                        .background(Circle().fill(tint.opacity(0.06)))
                        .frame(width: 28, height: 28)

                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(tint)
                }

                if isLast {
                    Spacer().frame(height: 6)
                } else {
                    Rectangle()
                        .fill(tint.opacity(0.25))
                        .frame(width: 1.5, height: 26) // Bounded static height to connect to next node!
                }
            }
            .frame(width: 28)

            // Column 2: Step Content
            content()
                .padding(.top, 4)
        }
    }
}

// MARK: - Local Tool Card Widgets

struct DeviceInfoWidgetView: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: iconName(for: row.0))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20, alignment: .center)

                    Text(row.0)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Text(row.1)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)

                if index < rows.count - 1 {
                    Divider().background(AppTheme.surfaceStroke)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func iconName(for key: String) -> String {
        let l = key.lowercased()
        if l.contains("device") { return "iphone" }
        if l.contains("system") { return "gearshape" }
        if l.contains("hardware") { return "cpu" }
        if l.contains("capability") { return "memorychip" }
        if l.contains("model") { return "sparkles" }
        return "info.circle"
    }
}

struct BatteryWidgetView: View {
    let output: String

    var body: some View {
        let parsed = parseBattery(output)
        HStack(spacing: 24) {
            // Visual Battery Cell (Horizontal)
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    // Outer shell
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.textSecondary.opacity(0.4), lineWidth: 3)
                        .frame(width: 80, height: 44)

                    // Liquid Fill
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(fillColor(parsed.level))
                        .frame(width: CGFloat(parsed.level) / 100.0 * 70.0, height: 34)
                        .padding(5)
                }

                // Terminal tip
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.textSecondary.opacity(0.4))
                    .frame(width: 4, height: 16)
            }
            .frame(width: 84, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(parsed.level)%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 4) {
                    if parsed.isCharging {
                        Image(systemName: "lightning.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.success)
                        Text("Charging")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.success)
                    } else {
                        Image(systemName: "battery.100")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("On battery")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func fillColor(_ level: Int) -> Color {
        if level > 20 { return AppTheme.success }
        return AppTheme.destructive
    }

    private func parseBattery(_ s: String) -> (level: Int, isCharging: Bool) {
        let cleaned = s.lowercased()
        var level = 50
        if let pctRange = cleaned.range(of: "\\d+%", options: .regularExpression) {
            let pctStr = String(cleaned[pctRange]).replacingOccurrences(of: "%", with: "")
            level = Int(pctStr) ?? 50
        }
        let isCharging = cleaned.contains("charging") || cleaned.contains("full")
        return (level, isCharging)
    }
}

struct CurrentTimeWidgetView: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: iconName(for: row.0))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accentSoft)
                        .frame(width: 20, alignment: .center)

                    Text(row.0)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Text(row.1)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.vertical, 10)

                if index < rows.count - 1 {
                    Divider().background(AppTheme.surfaceStroke)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func iconName(for key: String) -> String {
        let l = key.lowercased()
        if l.contains("time") { return "clock" }
        if l.contains("date") { return "calendar" }
        if l.contains("zone") { return "globe" }
        return "info.circle"
    }
}

struct CalculatorWidgetView: View {
    let expression: String
    let result: String

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack {
                Spacer()
                Text(expressionFormatted)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Spacer()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
    }

    private var expressionFormatted: String {
        var expr = expression
            .replacingOccurrences(of: "*", with: " × ")
            .replacingOccurrences(of: "/", with: " ÷ ")
            .replacingOccurrences(of: "sqrt", with: "√")

        let cleanedResult = result.replacingOccurrences(of: "Result:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        var formattedResult = cleanedResult
        if let val = Double(cleanedResult) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 8
            if let formatted = formatter.string(from: NSNumber(value: val)) {
                formattedResult = formatted
            }
        }

        return "\(expr) = \(formattedResult)"
    }
}

struct SearchChatsWidgetView: View {
    let output: String
    let sessions: [ChatSession]

    var body: some View {
        let parsed = parseOutput(output)
        VStack(alignment: .leading, spacing: 10) {
            Text("Found \(parsed.count) relevant chat\(parsed.count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(parsed.enumerated()), id: \.offset) { index, match in
                    let sessionInfo = findSessionInfo(match.title)
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)

                            Text("\(sessionInfo.dateStr) • \(sessionInfo.msgCount) messages")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())

                    if index < parsed.count - 1 {
                        Divider().background(AppTheme.surfaceStroke)
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(AppTheme.panel.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
            )
        }
    }

    struct Match {
        let title: String
        let role: String
        let excerpt: String
    }

    private func parseOutput(_ text: String) -> [Match] {
        var matches: [Match] = []
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var currentTitle = ""
        var currentRole = ""
        var currentExcerpt = ""

        for line in lines {
            if line.hasPrefix("[") && line.contains("—") {
                if !currentTitle.isEmpty {
                    matches.append(Match(title: currentTitle, role: currentRole, excerpt: currentExcerpt))
                    currentExcerpt = ""
                }
                if let bracketEndIdx = line.firstIndex(of: "]") {
                    let rest = line[line.index(after: bracketEndIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts = rest.split(separator: "—", maxSplits: 1)
                    if parts.count == 2 {
                        currentTitle = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        currentRole = parts[1].replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        currentTitle = String(rest)
                        currentRole = "Assistant"
                    }
                }
            } else if !currentTitle.isEmpty && !line.hasPrefix("Found ") {
                if currentExcerpt.isEmpty {
                    currentExcerpt = line
                } else {
                    currentExcerpt += " " + line
                }
            }
        }

        if !currentTitle.isEmpty {
            matches.append(Match(title: currentTitle, role: currentRole, excerpt: currentExcerpt))
        }

        return matches
    }

    private func findSessionInfo(_ title: String) -> (dateStr: String, msgCount: Int) {
        if let session = sessions.first(where: { $0.title.lowercased() == title.lowercased() }) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let dateStr = formatter.string(from: session.updatedAt)
            return (dateStr, session.messages.count)
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return (formatter.string(from: Date()), 6)
    }
}

struct ReadDocumentWidgetView: View {
    let output: String
    let attachments: [ChatAttachment]

    var body: some View {
        let docInfo = findDocumentInfo(output)
        let keyPoints = extractKeyPoints(output)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(docInfo.isPDF ? Color(red: 0.90, green: 0.22, blue: 0.20) : AppTheme.textSecondary.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: docInfo.isPDF ? "doc.richtext.fill" : "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(docInfo.isPDF ? .white : AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(docInfo.fileName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(docInfo.pages) page\(docInfo.pages == 1 ? "" : "s") • \(docInfo.sizeStr)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
            }
            .padding(10)
            .background(AppTheme.panel.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
            )

            if !keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key points")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(keyPoints, id: \.self) { pt in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.accent)
                                Text(pt)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func findDocumentInfo(_ text: String) -> (fileName: String, isPDF: Bool, pages: Int, sizeStr: String) {
        let firstLine = text.split(separator: "\n").first.map { String($0) } ?? ""
        let cleaned = firstLine.replacingOccurrences(of: "##", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        let isPDF = cleaned.lowercased().hasSuffix(".pdf")
        let fileName = cleaned.isEmpty ? "document.txt" : cleaned

        if let attachment = attachments.first(where: { $0.fileName.lowercased() == fileName.lowercased() }) {
            let size = attachment.rawData?.count ?? (attachment.extractedText?.count ?? 2000) * 2
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            let pages = max(1, (attachment.extractedText?.count ?? 0) / 1800)
            return (fileName, isPDF, pages, sizeStr)
        }

        return (fileName, isPDF, 12, "1.8 MB")
    }

    private func extractKeyPoints(_ text: String) -> [String] {
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var points: [String] = []

        var contentLines: [String] = []
        for line in lines {
            if line.hasPrefix("##") || line.hasPrefix("Error:") || line.isEmpty { continue }
            if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") {
                let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-* "))
                if !cleaned.isEmpty { points.append(cleaned) }
            } else {
                contentLines.append(line)
            }
            if points.count >= 4 { break }
        }

        if points.isEmpty {
            let fullContent = contentLines.joined(separator: " ")
            let sentences = fullContent.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            for sent in sentences {
                let cleaned = sent.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count > 15 {
                    points.append(cleaned + ".")
                }
                if points.count >= 4 { break }
            }
        }

        return points
    }
}

struct LocalToolResultCard: View {
    @Environment(AppStateStore.self) private var store
    let toolName: String
    let output: String
    let attachments: [ChatAttachment]
    let duration: Double?

    @State private var isCollapsed = false

    private var title: String {
        switch toolName.lowercased() {
        case "calculate": return "Calculated"
        case "get_current_time": return "Read current time"
        case "get_device_info": return "Read device info"
        case "get_battery_level": return "Read battery"
        case "search_chats": return "Searched chat history"
        case "read_document": return "Read document"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var icon: String {
        switch toolName.lowercased() {
        case "calculate": return "function"
        case "get_current_time": return "clock"
        case "get_device_info": return "iphone"
        case "get_battery_level": return "battery.100percent"
        case "search_chats": return "message.badge.filled.and.checkmark"
        case "read_document": return "doc.text"
        default: return "checkmark.circle"
        }
    }

    private var tint: Color {
        switch toolName.lowercased() {
        case "calculate": return Color(red: 0.44, green: 0.64, blue: 0.95)
        case "get_current_time": return Color(red: 0.58, green: 0.52, blue: 0.90)
        case "get_device_info": return AppTheme.accent
        case "get_battery_level": return Color(red: 0.29, green: 0.72, blue: 0.45)
        case "search_chats": return Color(red: 0.18, green: 0.78, blue: 0.72)
        case "read_document": return Color(red: 0.18, green: 0.78, blue: 0.72)
        default: return AppTheme.accent
        }
    }

    private var durationFormatted: String {
        guard let duration else { return "0.2s" }
        return String(format: "%.1fs", duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(tint.opacity(0.12)))

                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("•  local tool")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.success)

                    Spacer()

                    Text(durationFormatted)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if !isCollapsed {
                Group {
                    switch toolName.lowercased() {
                    case "calculate":
                        let expr = CalculateTool.extractExpression(output) ?? ""
                        CalculatorWidgetView(expression: expr, result: output)
                    case "get_battery_level":
                        BatteryWidgetView(output: output)
                    case "get_current_time":
                        CurrentTimeWidgetView(rows: parseRows(output))
                    case "get_device_info":
                        DeviceInfoWidgetView(rows: parseRows(output))
                    case "search_chats":
                        SearchChatsWidgetView(output: output, sessions: store.chatSessions)
                    case "read_document":
                        ReadDocumentWidgetView(output: output, attachments: attachments)
                    default:
                        // Fallback key-value rows
                        VStack(spacing: 0) {
                            let rows = parseRows(output)
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(row.0)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(width: 92, alignment: .leading)

                                    Text(row.1)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 8)

                                if index < rows.count - 1 {
                                    Divider().background(AppTheme.surfaceStroke)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(AppTheme.panelRaised.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 0.6)
        )
    }

    private func parseRows(_ output: String) -> [(String, String)] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var parsed: [(String, String)] = []
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty && !v.isEmpty {
                    parsed.append((k, v))
                }
            }
        }
        if parsed.isEmpty {
            parsed.append(("Result", output))
        }
        return parsed
    }
}

struct AssistantWorkingPlaceholder: View {
    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accent)
            Text("Working on it")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

struct CompactSourcesList: View {
    let citations: [SearchCitation]

    private let searchColor = Color(red: 0.18, green: 0.78, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(citations.prefix(5).enumerated()), id: \.element.id) { index, citation in
                Link(destination: citation.url) {
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(searchColor))
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(citation.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text(domainName(for: citation.url))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(searchColor.opacity(0.6))
                            .padding(.top, 3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if index < min(citations.count, 5) - 1 {
                    Divider()
                        .background(AppTheme.surfaceStroke)
                        .padding(.leading, 36)
                }
            }
        }
        .background(AppTheme.panelRaised.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 0.5)
        )
    }

    private func domainName(for url: URL) -> String {
        guard let host = url.host else { return "web" }
        return host.lowercased().replacingOccurrences(of: "www.", with: "")
    }
}

struct ThinkingDetailCard: View {
    let thinkingContent: String
    let isStreaming: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(width: 2)
                .clipShape(Capsule())

            Text(thinkingContent + (isStreaming ? "​" : ""))
                .font(.appBody(12))
                .italic()
                .foregroundStyle(tint.opacity(0.88))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) {
                    if isStreaming {
                        StreamingCursorView(color: tint)
                    }
                }
        }
        .padding(10)
        .background(tint.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Streaming cursor & dots

struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(phase == i ? 1 : 0.3)
                    .scaleEffect(phase == i ? 1.2 : 0.8)
            }
        }
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

struct StreamingCursorView: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: 13)
            .opacity(visible ? 1 : 0)
            .onReceive(Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    visible.toggle()
                }
            }
    }
}

struct SearchCitationsFooter: View {
    let citations: [SearchCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.18, green: 0.78, blue: 0.72))
                Text("SOURCES")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        Link(destination: citation.url) {
                            HStack(spacing: 8) {
                                // Index badge
                                Text("\(index + 1)")
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Circle().fill(Color(red: 0.18, green: 0.78, blue: 0.72)))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(citation.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(domainName(for: citation.url))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textTertiary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: 120, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 6)
    }

    private func domainName(for url: URL) -> String {
        guard let host = url.host else { return "web" }
        return host.lowercased().replacingOccurrences(of: "www.", with: "")
    }
}
