import Foundation
import Security

enum SubscriptionKeychain {
    private static let service = "com.hinaw.customize-sub-4-tokens"
    private static let adminAPIKeyAccount = "sub2api-admin-api-key"
    private static let accessTokenAccount = "sub2api-access-token"
    private static let refreshTokenAccount = "sub2api-refresh-token"

    static func readAdminAPIKey() -> String {
        read(account: adminAPIKeyAccount)
    }

    static func readToken() -> String {
        read(account: accessTokenAccount)
    }

    static func readRefreshToken() -> String {
        read(account: refreshTokenAccount)
    }

    private static func read(account: String) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func saveToken(_ token: String) throws {
        try save(token, account: accessTokenAccount)
    }

    static func saveAdminAPIKey(_ key: String) throws {
        try save(key, account: adminAPIKeyAccount)
    }

    static func saveRefreshToken(_ token: String) throws {
        try save(token, account: refreshTokenAccount)
    }

    private static func save(_ token: String, account: String) throws {
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            return
        }
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func deleteToken() {
        delete(account: accessTokenAccount)
    }

    static func deleteAdminAPIKey() {
        delete(account: adminAPIKeyAccount)
    }

    static func deleteRefreshToken() {
        delete(account: refreshTokenAccount)
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
