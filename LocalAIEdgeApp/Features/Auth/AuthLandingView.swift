import SwiftUI

struct AuthLandingView: View {
    @Environment(AuthStateStore.self) private var authStore

    @State private var displayName = ""
    @State private var email = ""
    @State private var deviceAuthNameHint = ""
    @State private var isProcessingDeviceAuth = false

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    credentialsSection
                    deviceAuthenticationSection
                    guestSection

                    if let error = authStore.lastErrorMessage, !error.isEmpty {
                        errorSection(error)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            AppBrandMark(size: 58)

            Text("Welcome to EdgeMind")
                .font(.appDisplay(30))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text("Use a local profile, iPhone authentication, or guest access to continue.")
                .font(.appBody(14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credentials")
                .font(.appCaps(14))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Display name", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(Capsule())

            TextField("Email (optional)", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(Capsule())

            Button {
                authStore.signInWithCredentials(displayName: displayName, email: email)
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                    Text("Continue with Credentials")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accentGradient)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
        .foregroundStyle(AppTheme.textPrimary)
        .font(.system(size: 14))
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private var deviceAuthenticationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone Authentication")
                .font(.appCaps(14))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Authenticate with \(authStore.deviceAuthLabel) or your device passcode.")
                .font(.appBody(12))
                .foregroundStyle(AppTheme.textTertiary)

            TextField("Name for device profile (optional)", text: $deviceAuthNameHint)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(Capsule())

            Button {
                guard !isProcessingDeviceAuth else { return }
                isProcessingDeviceAuth = true
                Task {
                    await authStore.signInWithDeviceAuthentication(displayNameHint: deviceAuthNameHint)
                    await MainActor.run {
                        isProcessingDeviceAuth = false
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "faceid")
                    Text(isProcessingDeviceAuth ? "Authenticating..." : "Continue with \(authStore.deviceAuthLabel)")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(authStore.canUseDeviceAuthentication ? AppTheme.accentGradient : LinearGradient(colors: [AppTheme.panelRaised, AppTheme.panelRaised], startPoint: .top, endPoint: .bottom))
                .foregroundStyle(authStore.canUseDeviceAuthentication ? .white : AppTheme.textTertiary)
                .clipShape(Capsule())
            }
            .disabled(!authStore.canUseDeviceAuthentication || isProcessingDeviceAuth)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .font(.system(size: 14))
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private var guestSection: some View {
        Button {
            authStore.continueAsGuest()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                Text("Continue as Guest")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(AppTheme.textSecondary)
            .background(AppTheme.controlFill)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
            )
        }
    }

    private func errorSection(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.warning)

            Text(error)
                .font(.appBody(12))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Button("Dismiss") {
                authStore.clearError()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .glassCard(cornerRadius: 16, padding: 12)
    }
}
