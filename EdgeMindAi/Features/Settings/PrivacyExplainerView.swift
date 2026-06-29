import SwiftUI

struct PrivacyExplainerView: View {
    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    policySection
                    dataSection
                    networkSection
                    rightsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Policy")
                .font(.appDisplay(30))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Edge Mind Ai is designed for local AI inference. Network requests are limited to actions you enable or start, such as model downloads and live search.")
                .font(.appBody(14))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var policySection: some View {
        policyCard(title: "Local by default", icon: "lock.fill") {
            privacyRow(icon: "checkmark.shield.fill", text: "Prompts, responses, settings, chat history, and profile data are stored on this device by default.")
            privacyRow(icon: "cpu.fill", text: "GGUF and MLX inference runs on device after a model is installed.")
            privacyRow(icon: "trash.slash.fill", text: "You can delete chat history and installed model files from inside the app.")
        }
    }

    private var dataSection: some View {
        policyCard(title: "Data stored by the app", icon: "internaldrive.fill") {
            privacyRow(icon: "person.crop.circle", text: "No account is required. The app creates an anonymous local guest profile automatically; optional profile details stay on this device.")
            privacyRow(icon: "message.fill", text: "Chat sessions are saved locally. Image attachments are downsampled before local persistence and inference.")
            privacyRow(icon: "key.fill", text: "Hugging Face tokens are stored in Keychain. Search API keys and gateway settings are stored locally in app settings.")
        }
    }

    private var networkSection: some View {
        policyCard(title: "Optional network use", icon: "network") {
            privacyRow(icon: "arrow.down.circle.fill", text: "Model downloads contact Hugging Face or the configured model host for the selected model file.")
            privacyRow(icon: "globe.americas.fill", text: "Live Search sends your search query to the provider you choose in Settings.")
            privacyRow(icon: "mic.fill", text: "Voice dictation uses Apple's speech recognition permission path when you choose to dictate prompts.")
        }
    }

    private var rightsSection: some View {
        policyCard(title: "Your choices", icon: "slider.horizontal.3") {
            privacyRow(icon: "wifi.slash", text: "Keep Live Search off after model installation for an offline-first chat experience.")
            privacyRow(icon: "arrow.counterclockwise.circle", text: "Reset the local profile from Settings without creating a remote account.")
            privacyRow(icon: "envelope.fill", text: "Use the support URL listed on the App Store page for privacy or data deletion requests.")
        }
    }

    private func policyCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                Text(title)
                    .font(.appDisplay(18))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 9) {
                content()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 0.7)
        )
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.success)
                .padding(.top, 2)

            Text(text)
                .font(.appBody(12))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
