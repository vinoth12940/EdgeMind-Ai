import Foundation
import Security

/// Shared Keychain primitives for the app's secrets (API keys, tokens).
/// Each secret owner supplies its own service/account pair so existing
/// entries (e.g. the HuggingFace token) stay readable.
enum KeychainSecretStore {

    static func save(_ value: String, service: String, account: String) {
        delete(service: service, account: account)
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

    static func read(service: String, account: String) -> String? {
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

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain storage for the web-search provider API key (Tavily/Brave/Serper).
/// The key lives ONLY here — `AppSettings.webSearchAPIKey` is an in-memory copy
/// that is deliberately excluded from the persisted settings JSON.
enum WebSearchKeyManager {

    private static let service = "io.example.PrivateEdgeChat.WebSearch"
    private static let account = "web_search_api_key"

    static var key: String? {
        get { KeychainSecretStore.read(service: service, account: account) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainSecretStore.save(newValue, service: service, account: account)
            } else {
                KeychainSecretStore.delete(service: service, account: account)
            }
        }
    }
}
