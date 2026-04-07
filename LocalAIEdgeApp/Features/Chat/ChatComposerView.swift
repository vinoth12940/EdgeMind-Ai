import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation

struct ChatComposerView: View {
    @Binding var prompt: String
    @Binding var liveSearchEnabled: Bool
    @Binding var attachedImage: UIImage?
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
    @State private var showVideoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showSearchNotConfigured = false

    private var canSend: Bool {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = attachedImage != nil
        return (hasText || hasImage) && !isSending
    }

    private var isSearchActiveTint: Color {
        liveSearchEnabled ? AppTheme.warning : AppTheme.textSecondary
    }

    var body: some View {
        VStack(spacing: 10) {
            attachmentPreview
            inputRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $attachedImage)
                .ignoresSafeArea()
        }
        .alert("Search Not Configured", isPresented: $showSearchNotConfigured) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Go to Settings → Web Search API and select a provider with an API key.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared())
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared())
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
        .onChange(of: selectedVideoItem) { _, newItem in
            Task {
                guard let newItem else { return }

                let storyboard: UIImage?
                if let movieURL = try? await newItem.loadTransferable(type: URL.self) {
                    storyboard = await Task.detached(priority: .userInitiated) {
                        Self.extractStoryboardImage(from: movieURL, frameCount: 4, maxDimension: 1024)
                    }.value
                } else {
                    storyboard = nil
                }

                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        attachedImage = storyboard
                    }
                    selectedVideoItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let image = attachedImage {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                        )

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

                Text("Image attached")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.top, 4)

                Spacer()
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    private var inputRow: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
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
                        Button { showVideoPicker = true } label: {
                            Label("Attach video", systemImage: "video")
                        }
                    }
                } label: {
                    composerRoundButton(icon: attachedImage != nil ? "photo.fill" : "plus", tint: attachedImage != nil ? AppTheme.accentSoft : AppTheme.textPrimary, fill: Color.white.opacity(attachedImage != nil ? 0.16 : 0.08))
                }

                TextField("Ask anything…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .lineLimit(1...6)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .focused($isFocused)
                    .foregroundStyle(.white)
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                isFocused
                                    ? AppTheme.accent.opacity(0.4)
                                    : Color.white.opacity(0.08),
                                lineWidth: isFocused ? 1.5 : 0.5
                            )
                            .animation(.easeOut(duration: 0.2), value: isFocused)
                    )
                    .frame(minHeight: 48)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button {
                                isFocused = false
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }

                if isSending, let onStop {
                    Button(action: onStop) {
                        composerRoundButton(icon: "stop.fill", tint: .white, fill: AppTheme.destructive)
                    }
                    .accessibilityLabel("Stop generation")
                } else if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(AppTheme.accent)
                            )
                    }
                    .accessibilityLabel("Send message")
                } else if voiceModeEnabled {
                    Button(action: onToggleVoiceInput) {
                        composerRoundButton(icon: isListening ? "stop.fill" : "waveform", tint: .white, fill: isListening ? AppTheme.destructive : AppTheme.warning)
                    }
                    .accessibilityLabel(isListening ? "Stop voice input" : "Start voice input")
                    .disabled(isSending)
                } else {
                    Button(action: onSend) {
                        composerRoundButton(icon: "arrow.up", tint: Color.white.opacity(0.28), fill: Color.white.opacity(0.06))
                    }
                    .accessibilityLabel("Send message")
                    .disabled(!canSend)
                }
            }

            if let voiceStatusMessage, !voiceStatusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)

                    Text(voiceStatusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()
                }
            }
        }
    }

    private func composerRoundButton(icon: String, tint: Color, fill: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(fill))
    }

    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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

    private static func extractStoryboardImage(from videoURL: URL, frameCount: Int, maxDimension: CGFloat) -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let durationSeconds = max(0.1, CMTimeGetSeconds(asset.duration))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let framePoints: [Double]
        if frameCount <= 1 {
            framePoints = [0.5]
        } else {
            framePoints = (0..<frameCount).map { idx in
                0.1 + (0.8 * Double(idx) / Double(frameCount - 1))
            }
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)

        for point in framePoints {
            let t = CMTime(seconds: durationSeconds * point, preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
                let frame = downsample(UIImage(cgImage: cg), maxDimension: maxDimension)
                frames.append(frame)
            }
        }

        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }
        return makeCollage(from: frames, maxDimension: maxDimension)
    }

    private static func makeCollage(from images: [UIImage], maxDimension: CGFloat) -> UIImage? {
        let columns = 2
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let tile = maxDimension / CGFloat(columns)
        let canvasSize = CGSize(width: tile * CGFloat(columns), height: tile * CGFloat(rows))
        let renderer = UIGraphicsImageRenderer(size: canvasSize)

        return renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))

            for (index, image) in images.enumerated() {
                let row = index / columns
                let col = index % columns
                let cell = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)

                let fitScale = min(cell.width / image.size.width, cell.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)
                let drawRect = CGRect(
                    x: cell.midX - drawSize.width / 2,
                    y: cell.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                image.draw(in: drawRect)
            }
        }
    }
}
