import Foundation
import Security

enum KeychainService {
    static let anthropicKey = "com.amiet.konomi.anthropic_key"
    static let tmdbKey = "com.amiet.konomi.tmdb_key"
    static let googleBooksKey = "com.amiet.konomi.google_books_key"

    @discardableResult
    nonisolated static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    @discardableResult
    nonisolated static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Convenience

    nonisolated static func saveAnthropic(_ key: String) { save(key: anthropicKey, value: key) }
    nonisolated static func loadAnthropic() -> String? { load(key: anthropicKey) }
    nonisolated static func deleteAnthropic() { delete(key: anthropicKey) }

    nonisolated static func saveTMDB(_ key: String) { save(key: tmdbKey, value: key) }
    nonisolated static func loadTMDB() -> String? { load(key: tmdbKey) }
    nonisolated static func deleteTMDB() { delete(key: tmdbKey) }

    nonisolated static func saveGoogleBooks(_ key: String) { save(key: googleBooksKey, value: key) }
    nonisolated static func loadGoogleBooks() -> String? { load(key: googleBooksKey) }
    nonisolated static func deleteGoogleBooks() { delete(key: googleBooksKey) }
}
