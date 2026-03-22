import AuthenticationServices
import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AuthStateStore {
    enum AuthMethod: String, Codable, Hashable {
        case appleID = "Apple ID"
        case credentials = "Credentials"
        case deviceAuth = "iPhone Authentication"
        case guest = "Guest"
    }

    struct UserProfile: Codable, Hashable {
        var id: UUID
        var displayName: String
        var email: String?
        var authMethod: AuthMethod
        var appleUserID: String?
        var createdAt: Date
        var lastLoginAt: Date
    }

    var isAuthenticated = false
    var profile: UserProfile?
    var lastErrorMessage: String?

    private static let profileKey = "persistedAuthProfile"

    init() {
        restorePersistedSession()
    }

    var deviceAuthLabel: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Device Passcode"
        }
    }

    var canUseDeviceAuthentication: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func continueAsGuest() {
        let guestProfile = UserProfile(
            id: UUID(),
            displayName: "Guest",
            email: nil,
            authMethod: .guest,
            appleUserID: nil,
            createdAt: .now,
            lastLoginAt: .now
        )
        completeSignIn(with: guestProfile)
    }

    func signInWithCredentials(displayName: String, email: String) {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 2 else {
            lastErrorMessage = "Enter a display name with at least 2 characters."
            return
        }

        let normalizedEmail = normalizeEmail(email)
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, normalizedEmail == nil {
            lastErrorMessage = "Enter a valid email address."
            return
        }

        let createdAt = profile?.createdAt ?? .now
        let localProfile = UserProfile(
            id: profile?.id ?? UUID(),
            displayName: trimmedName,
            email: normalizedEmail,
            authMethod: .credentials,
            appleUserID: nil,
            createdAt: createdAt,
            lastLoginAt: .now
        )
        completeSignIn(with: localProfile)
    }

    func handleAppleSignIn(_ credential: ASAuthorizationAppleIDCredential) {
        let existingAppleProfile: UserProfile? = {
            guard let profile, profile.appleUserID == credential.user else { return nil }
            return profile
        }()

        let formatter = PersonNameComponentsFormatter()
        let fullName = credential.fullName.map { formatter.string(from: $0) } ?? ""
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName: String
        if !trimmedName.isEmpty {
            resolvedName = trimmedName
        } else if let existingName = existingAppleProfile?.displayName {
            resolvedName = existingName
        } else {
            resolvedName = "Apple User"
        }

        let resolvedEmail = credential.email ?? existingAppleProfile?.email
        let createdAt = existingAppleProfile?.createdAt ?? .now
        let appleProfile = UserProfile(
            id: existingAppleProfile?.id ?? UUID(),
            displayName: resolvedName,
            email: resolvedEmail,
            authMethod: .appleID,
            appleUserID: credential.user,
            createdAt: createdAt,
            lastLoginAt: .now
        )
        completeSignIn(with: appleProfile)
    }

    func signInWithDeviceAuthentication(displayNameHint: String) async {
        await evaluateDeviceAuthentication(reason: "Authenticate to continue into your local AI workspace.") { [self] existingProfile in
            let trimmedHint = displayNameHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName: String
            if !trimmedHint.isEmpty {
                resolvedName = trimmedHint
            } else if let existingProfile {
                resolvedName = existingProfile.displayName
            } else {
                resolvedName = "iPhone User"
            }

            let createdAt = existingProfile?.createdAt ?? .now
            let profile = UserProfile(
                id: existingProfile?.id ?? UUID(),
                displayName: resolvedName,
                email: existingProfile?.email,
                authMethod: .deviceAuth,
                appleUserID: existingProfile?.appleUserID,
                createdAt: createdAt,
                lastLoginAt: .now
            )
            self.completeSignIn(with: profile)
        }
    }

    @discardableResult
    func reauthenticateCurrentUser() async -> Bool {
        guard isAuthenticated else {
            lastErrorMessage = "No active session to re-authenticate."
            return false
        }

        var succeeded = false
        await evaluateDeviceAuthentication(reason: "Confirm your identity to access profile actions.") { [self] existingProfile in
            guard var existingProfile else {
                self.lastErrorMessage = "No saved profile found."
                return
            }
            existingProfile.lastLoginAt = .now
            self.completeSignIn(with: existingProfile)
            succeeded = true
        }
        return succeeded
    }

    func signOut() {
        isAuthenticated = false
        profile = nil
        lastErrorMessage = nil
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func completeSignIn(with profile: UserProfile) {
        self.profile = profile
        self.isAuthenticated = true
        self.lastErrorMessage = nil
        persist(profile: profile)
    }

    private func evaluateDeviceAuthentication(
        reason: String,
        onSuccess: @MainActor @escaping (UserProfile?) -> Void
    ) async {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            lastErrorMessage = authError?.localizedDescription ?? "Device authentication is unavailable."
            return
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                onSuccess(profile)
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                break
            default:
                lastErrorMessage = error.localizedDescription
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persist(profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.profileKey)
    }

    private func restorePersistedSession() {
        guard let data = UserDefaults.standard.data(forKey: Self.profileKey),
              let decodedProfile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            isAuthenticated = false
            profile = nil
            return
        }

        profile = decodedProfile
        isAuthenticated = true
    }

    private func normalizeEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let isValid = trimmed.contains("@")
            && trimmed.contains(".")
            && !trimmed.contains(" ")
        return isValid ? trimmed : nil
    }
}
