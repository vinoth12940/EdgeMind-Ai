import AuthenticationServices
import SwiftUI

struct AuthLandingView: View {
    @Environment(AuthStateStore.self) private var authStore

    @State private var displayName = ""
    @State private var email = ""
    @State private var deviceAuthNameHint = ""
    @State private var isProcessingDeviceAuth = false

    var body: some View {
        ZStack {
            AppTheme.meshBackground.ignoresSafeArea()
            AppTheme.glow.opacity(0.16).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    appleSignInSection
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
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.16))
                    .frame(width: 86, height: 86)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            Text("Welcome to Local AI Edge")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text("Sign in with Apple (iCloud), local credentials, or iPhone authentication to continue.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var appleSignInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple ID")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Uses your iCloud/Apple account through Sign in with Apple.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        authStore.lastErrorMessage = "Unable to read Apple sign-in response."
                        return
                    }
                    authStore.handleAppleSignIn(credential)
                case .failure(let error):
                    authStore.lastErrorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credentials")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Display name", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField("Email (optional)", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                authStore.signInWithCredentials(displayName: displayName, email: email)
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                    Text("Continue with Credentials")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppTheme.accent.opacity(0.18))
                .foregroundStyle(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .foregroundStyle(AppTheme.textPrimary)
        .font(.system(size: 14))
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private var deviceAuthenticationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone Authentication")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Authenticate with \(authStore.deviceAuthLabel) or your device passcode.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)

            TextField("Name for device profile (optional)", text: $deviceAuthNameHint)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.panelRaised.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(authStore.canUseDeviceAuthentication ? AppTheme.success.opacity(0.18) : AppTheme.panelRaised)
                .foregroundStyle(authStore.canUseDeviceAuthentication ? AppTheme.success : AppTheme.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            .padding(.vertical, 10)
            .foregroundStyle(AppTheme.textSecondary)
            .background(AppTheme.panel.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }

    private func errorSection(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.warning)

            Text(error)
                .font(.system(size: 12))
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
