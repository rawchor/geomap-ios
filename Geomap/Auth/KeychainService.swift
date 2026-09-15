import Foundation
import Security

/// Wraps the Security framework's Keychain calls to store the JWT securely
/// — this is iOS's equivalent of web's httpOnly cookie approach.
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.geomap.ios.auth"
    private let tokenAccount = "authToken"

    private init() {}

    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(baseQuery() as CFDictionary, attributesToUpdate as CFDictionary)
        }
    }

    func getToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
    }
}
