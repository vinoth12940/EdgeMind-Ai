import Foundation

/// Manages HuggingFace API token storage in the iOS Keychain.
enum HFTokenManager {

    // Service/account strings predate KeychainSecretStore — do not change them,
    // or existing users' saved tokens become unreadable.
    private static let service = "io.example.PrivateEdgeChat.HuggingFace"
    private static let account = "hf_api_token"

    static var token: String? {
        get { KeychainSecretStore.read(service: service, account: account) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainSecretStore.save(newValue, service: service, account: account)
            } else {
                KeychainSecretStore.delete(service: service, account: account)
            }
        }
    }

    static var hasToken: Bool {
        token != nil
    }

    /// Build an authorized URLRequest for HuggingFace downloads.
    static func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
