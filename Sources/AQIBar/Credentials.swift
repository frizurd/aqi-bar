import Foundation
import Security
import LocalAuthentication

enum Credentials {
    private static let service = "local.frizurd.aqibar"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "iqair"]
    }

    static var existingPluginKey: String {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sketchybar/secrets/iqair.key")
        return ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var savedKey: String {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        search[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static var activeKey: String {
        let saved = savedKey
        return saved.isEmpty ? existingPluginKey : saved
    }

    static func importExistingPluginKey() {
        guard savedKey.isEmpty else { return }
        let existing = existingPluginKey
        if !existing.isEmpty { try? save(existing) }
    }

    static func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AQIBarError.message("Enter an IQAir API key first.") }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw AQIBarError.message("Couldn’t save the API key to your Mac’s Keychain (\(status)).")
        }
    }
}

enum AQIBarError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
