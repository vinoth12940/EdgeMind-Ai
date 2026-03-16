import Foundation
import Security

/// Manages HuggingFace API token storage in the iOS Keychain.
enum HFTokenManager {

    private static let service = "io.example.PrivateEdgeChat.HuggingFace"
    private static let account = "hf_api_token"

    // MARK: - Public API

    static var token: String? {
        get { read() }
        set {
            if let newValue, !newValue.isEmpty {
                save(newValue)
            } else {
                delete()
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

    // MARK: - Keychain Operations

    private static func save(_ value: String) {
        delete() // remove old entry first

        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
