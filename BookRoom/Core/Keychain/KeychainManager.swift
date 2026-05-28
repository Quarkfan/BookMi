import Foundation
import Security

/// Keychain wrapper for sensitive data (API keys, passcodes)
final class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    // MARK: - API Key

    func getLLMAPIKey() -> String? {
        get(key: "com.bookroom.llm-api-key")
    }

    func setLLMAPIKey(_ key: String) -> Bool {
        set(key: "com.bookroom.llm-api-key", value: key)
    }

    func deleteLLMAPIKey() {
        delete(key: "com.bookroom.llm-api-key")
    }

    // MARK: - Passcode Hash

    func getPasscodeHash() -> String? {
        get(key: "com.bookroom.passcode-hash")
    }

    func setPasscodeHash(_ hash: String) -> Bool {
        set(key: "com.bookroom.passcode-hash", value: hash)
    }

    func deletePasscodeHash() {
        delete(key: "com.bookroom.passcode-hash")
    }

    // MARK: - Generic

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func set(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let newQuery = query.merging(attributes) { $1 }
            return SecItemAdd(newQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
