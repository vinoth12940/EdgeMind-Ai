import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct ChatComposerView: View {
    @Binding var prompt: String
    @Binding var liveSearchEnabled: Bool
    @Binding var attachedImage: UIImage?
    @Binding var attachedDocuments: [ChatAttachment]
    @Binding var isInputFocused: Bool
    let voiceModeEnabled: Bool
    let isListening: Bool
    let voiceStatusMessage: String?
    let isVisionModel: Bool
    let isSending: Bool
    let isSearchConfigured: Bool
    let onSend: () -> Void
    let onToggleVoiceInput: () -> Void
    var onStop: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSearchNotConfigured = false
    @State private var attachmentError: String?
    @State private var previewItem: AttachmentPreviewItem?

    private var canSend: Bool {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = attachedImage != nil
        let hasDocument = !attachedDocuments.isEmpty
        return (hasText || hasImage || hasDocument) && !isSending
    }

    private var isSearchActiveTint: Color {
        liveSearchEnabled ? AppTheme.warning : AppTheme.textSecondary
    }

    var body: some View {
        VStack(spacing: 6) {
            utilityLane
            attachmentPreview
            
            // Unified Composer Capsule
            HStack(alignment: .bottom, spacing: 8) {
                // Left Attachment Button
                Menu {
                    Button {
                        if !liveSearchEnabled && !isSearchConfigured {
                            showSearchNotConfigured = true
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            liveSearchEnabled.toggle()
                        }
                    } label: {
                        Label(liveSearchEnabled ? "Turn search off" : "Turn search on", systemImage: liveSearchEnabled ? "sparkle.magnifyingglass" : "bolt.slash")
                    }

                    if isVisionModel {
                        Button { showCamera = true } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                        Button { showPhotoPicker = true } label: {
                            Label("Attach photo", systemImage: "photo.on.rectangle")
                        }
                    }

                    Button { showDocumentPicker = true } label: {
                        Label("Attach file", systemImage: "doc.badge.plus")
                    }
                } label: {
                    let hasAttachment = attachedImage != nil || !attachedDocuments.isEmpty
                    Image(systemName: hasAttachment ? "paperclip" : "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(hasAttachment ? AppTheme.accentSoft : AppTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(hasAttachment ? 0.16 : 0.06)))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.bottom, 3)

                // Text Input
                TextField("Ask anything…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.appBody(15))
                    .lineLimit(1...6)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .focused($isFocused)
                    .foregroundStyle(.white)
                    .tint(AppTheme.accent)
                    .padding(.vertical, 8)
                
                // Right Action Button (Send / Stop / Microphone)
                Group {
                    if isSending, let onStop {
                        Button(action: onStop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(AppTheme.destructive))
                        }
                        .accessibilityLabel("Stop generation")
                    } else if canSend {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(AppTheme.accentGradient))
                        }
                        .accessibilityLabel("Send message")
                    } else if voiceModeEnabled {
                        Button(action: onToggleVoiceInput) {
                            Image(systemName: isListening ? "stop.fill" : "waveform")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(isListening ? AppTheme.destructive : AppTheme.warning))
                        }
                        .accessibilityLabel(isListening ? "Stop voice input" : "Start voice input")
                        .disabled(isSending)
                    } else {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.04)))
                        }
                        .accessibilityLabel("Send message")
                        .disabled(true)
                    }
                }
                .padding(.trailing, 4)
                .padding(.bottom, 5)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isFocused
                            ? AppTheme.accent.opacity(0.35)
                            : Color.white.opacity(0.08),
                        lineWidth: isFocused ? 1.2 : 0.6
                    )
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            )
            
            if let voiceStatusMessage, !voiceStatusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)

                    Text(voiceStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()
                }
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .background(Color.clear)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $attachedImage)
                .ignoresSafeArea()
        }
        .alert("Search Not Configured", isPresented: $showSearchNotConfigured) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Go to Settings → Web Search API and select a provider with an API key.")
        }
        .alert("Attachment Error", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
        .sheet(item: $previewItem) { item in
            AttachmentPreviewSheet(item: item)
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: DocumentExtractionService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        let attachment = try DocumentExtractionService.attachment(from: url)
                        await MainActor.run {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                attachedDocuments.append(attachment)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            attachmentError = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                attachmentError = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared())
        .onAppear {
            isFocused = isInputFocused
        }
        .onChange(of: isFocused) { _, newValue in
            isInputFocused = newValue
        }
        .onChange(of: isInputFocused) { _, newValue in
            if isFocused != newValue {
                isFocused = newValue
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let newItem else { return }

                let loadedImage: UIImage?
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    loadedImage = Self.downsample(data: data, maxPixelSize: 1024)
                } else {
                    loadedImage = nil
                }

                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        attachedImage = loadedImage
                    }
                    selectedPhotoItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private var utilityLane: some View {
        if attachedImage != nil || !attachedDocuments.isEmpty || isListening {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statusPill(
                        icon: liveSearchEnabled ? "globe.badge.chevron.backward" : "lock.fill",
                        label: liveSearchEnabled ? "Search On" : (isSearchConfigured ? "Search Ready" : "Offline"),
                        color: liveSearchEnabled ? AppTheme.warning : AppTheme.textSecondary
                    )

                    if isVisionModel {
                        statusPill(icon: "photo.on.rectangle.angled", label: "Vision Lane", color: AppTheme.capVision)
                    }

                    if voiceModeEnabled {
                        statusPill(icon: isListening ? "waveform.circle.fill" : "mic.fill", label: isListening ? "Listening" : "Voice Ready", color: isListening ? AppTheme.warning : AppTheme.accentSoft)
                    }

                    if attachedImage != nil || !attachedDocuments.isEmpty {
                        statusPill(icon: "paperclip", label: "Attachment Added", color: AppTheme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if attachedImage != nil || !attachedDocuments.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                if let image = attachedImage {
                    ZStack(alignment: .topTrailing) {
                        Button {
                            previewItem = .image(image, title: "Image")
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.black.opacity(0.54)))
                                        .padding(5)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview image attachment")

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                attachedImage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)).frame(width: 18, height: 18))
                        }
                        .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if attachedImage != nil {
                        Text("Image attached")
                            .font(.appBody(12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    ForEach(attachedDocuments) { attachment in
                        HStack(spacing: 6) {
                            Button {
                                previewItem = .document(attachment)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(attachment.fileName)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .opacity(0.62)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview \(attachment.fileName)")

                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    attachedDocuments.removeAll { $0.id == attachment.id }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                        .font(.appBody(12))
                        .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .padding(.top, 4)

                Spacer()
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    private func composerRoundButton(icon: String, tint: Color, fill: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(Circle().fill(fill))
    }

    private func statusPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.appCaps(10))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    nonisolated private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize))
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

}
