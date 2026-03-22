import SwiftUI
import PhotosUI
import ImageIO

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
    let onSend: () -> Void
    let onToggleVoiceInput: () -> Void
    var onStop: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var canSend: Bool {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = attachedImage != nil
        return (hasText || hasImage) && !isSending
    }

    private var shouldShowUtilityRow: Bool {
        !isFocused || attachedImage != nil || isVisionModel
    }

    var body: some View {
        VStack(spacing: 10) {
            if shouldShowUtilityRow {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            liveSearchEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: liveSearchEnabled ? "sparkle.magnifyingglass" : "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                            Text(liveSearchEnabled ? "Search On" : "Search")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(liveSearchEnabled ? AppTheme.warning : AppTheme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(liveSearchEnabled ? AppTheme.warning.opacity(0.12) : AppTheme.panelRaised)
                        )
                        .overlay(
                            Capsule()
                                .stroke(liveSearchEnabled ? AppTheme.warning.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }

                    if isVisionModel {
                        Menu {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                            }

                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: attachedImage != nil ? "photo.badge.checkmark" : "photo.badge.plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(attachedImage != nil ? "Image Ready" : "Add Photo")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(attachedImage != nil ? AppTheme.accent : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(attachedImage != nil ? AppTheme.accent.opacity(0.12) : AppTheme.panelRaised)
                            )
                        }
                    }

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Attached image preview
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

            // Input bar
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask anything…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppTheme.panelRaised.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                isFocused ? AppTheme.accent.opacity(0.4) : AppTheme.hairline,
                                lineWidth: isFocused ? 1.5 : 1
                            )
                            .animation(.easeOut(duration: 0.2), value: isFocused)
                    )
                    .frame(minHeight: 52)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }

                if voiceModeEnabled {
                    Button(action: onToggleVoiceInput) {
                        Image(systemName: isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isListening ? Color.red : AppTheme.warning)
                            )
                            .scaleEffect(isListening ? 1.0 : 0.94)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isListening)
                    }
                    .disabled(isSending)
                }

                if isSending, let onStop {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.red)
                            )
                            .scaleEffect(1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSending)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSend ? .white : AppTheme.textTertiary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(canSend ? AppTheme.accent : AppTheme.panelRaised)
                            )
                            .scaleEffect(canSend ? 1.0 : 0.9)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: canSend)
                    }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppTheme.panel.opacity(0.6))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .shadow(color: AppTheme.softShadow.opacity(0.35), radius: 18, x: 0, y: -6)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $attachedImage)
                .ignoresSafeArea()
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
}
