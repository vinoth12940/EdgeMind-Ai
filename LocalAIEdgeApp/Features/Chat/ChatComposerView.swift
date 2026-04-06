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
    let isSearchConfigured: Bool
    let onSend: () -> Void
    let onToggleVoiceInput: () -> Void
    var onStop: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSearchNotConfigured = false

    private var canSend: Bool {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = attachedImage != nil
        return (hasText || hasImage) && !isSending
    }

    private var shouldShowUtilityRow: Bool {
        !isFocused
    }

    var body: some View {
        VStack(spacing: 6) {


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
                if isVisionModel {
                    Menu {
                        Button(action: {}) {
                            Label("Attach file", systemImage: "folder")
                        }
                        Button { showCamera = true } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                        Button { showPhotoPicker = true } label: {
                            Label("Attach photo", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(attachedImage != nil ? AppTheme.accent : .white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(attachedImage != nil ? AppTheme.accent.opacity(0.12) : Color(red: 0.14, green: 0.16, blue: 0.22))
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        attachedImage != nil
                                        ? LinearGradient(colors: [AppTheme.accent.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: attachedImage != nil)
                }

                Button {
                    if !liveSearchEnabled && !isSearchConfigured {
                        showSearchNotConfigured = true
                        return
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        liveSearchEnabled.toggle()
                    }
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(liveSearchEnabled ? AppTheme.warning : .white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(liveSearchEnabled ? AppTheme.warning.opacity(0.15) : Color(red: 0.14, green: 0.16, blue: 0.22))
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    liveSearchEnabled
                                    ? LinearGradient(colors: [AppTheme.warning.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: liveSearchEnabled)
                TextField("Ask anything…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .lineLimit(1...6)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .focused($isFocused)
                    .foregroundStyle(.white)
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(red: 0.14, green: 0.16, blue: 0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isFocused 
                                    ? LinearGradient(
                                        colors: [AppTheme.accent.opacity(0.6), AppTheme.accentSoft.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                lineWidth: isFocused ? 2 : 1
                            )
                            .animation(.easeOut(duration: 0.25), value: isFocused)
                    )
                    .shadow(
                        color: isFocused ? AppTheme.accent.opacity(0.3) : .clear,
                        radius: isFocused ? 16 : 0,
                        x: 0,
                        y: isFocused ? 4 : 0
                    )
                    .animation(.easeOut(duration: 0.25), value: isFocused)
                    .frame(minHeight: 54)
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
                    .accessibilityLabel(isListening ? "Stop voice input" : "Start voice input")
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
                    .accessibilityLabel("Stop generation")
                } else {
                    Button(action: onSend) {
                        ZStack {
                            if canSend {
                                // Vibrant glow effect
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                AppTheme.accent.opacity(0.5),
                                                AppTheme.accent.opacity(0.2),
                                                .clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 35
                                        )
                                    )
                                    .frame(width: 70, height: 70)
                                    .blur(radius: 12)
                            }
                            
                            // Main button
                            Circle()
                                .fill(
                                    canSend
                                    ? LinearGradient(
                                        colors: [
                                            Color(red: 0.20, green: 0.75, blue: 1.0),
                                            Color(red: 0.34, green: 0.44, blue: 0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [
                                            Color(red: 0.10, green: 0.12, blue: 0.17),
                                            Color(red: 0.10, green: 0.12, blue: 0.17)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            canSend
                                                ? Color.white.opacity(0.2)
                                                : Color.white.opacity(0.05),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(canSend ? .white : Color.white.opacity(0.25))
                                .shadow(
                                    color: canSend ? .black.opacity(0.2) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        }
                        .scaleEffect(canSend ? 1.0 : 0.85)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: canSend)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Base blur layer
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Solid overlay for better contrast
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.09, blue: 0.13).opacity(0.95),
                                Color(red: 0.06, green: 0.07, blue: 0.11).opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isFocused
                            ? [
                                AppTheme.accent.opacity(0.6),
                                AppTheme.accentSoft.opacity(0.4),
                                AppTheme.accent.opacity(0.6)
                            ]
                            : [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.1)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused ? 2 : 1.5
                )
                .animation(.easeOut(duration: 0.3), value: isFocused)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: -8)
        .shadow(
            color: isFocused ? AppTheme.accent.opacity(0.4) : .clear,
            radius: isFocused ? 32 : 0,
            x: 0,
            y: isFocused ? -12 : 0
        )
        .animation(.easeOut(duration: 0.3), value: isFocused)
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
