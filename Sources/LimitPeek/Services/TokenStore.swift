import Foundation
import Security

/// The OAuth token pair for one account. Keychain and memory only, never
/// UserDefaults, a file, or a log line.
struct TokenPair: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]

    /// Refresh before the server would reject it, so a poll never fails first.
    func needsRefresh(now: Date = Date(), margin: TimeInterval = 300) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

enum KeychainError: Error, LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let code):
            let message = SecCopyErrorMessageString(code, nil) as String? ?? "unknown"
            return "Keychain error \(code): \(message)"
        }
    }
}

enum TokenStore {
    static let service = "dev.nevermind.LimitPeek.oauth"

    static func save(_ pair: TokenPair, for accountID: String) throws {
        let data = try JSONEncoder().encode(pair)

        // Update in place so the item's ACL survives a rotation.
        let updateStatus = withQuery(accountID) { query in
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
        if updateStatus == errSecSuccess { return }

        let addStatus = withQuery(accountID) { query in
            var attributes = query
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil)
        }
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    static func load(for accountID: String) throws -> TokenPair? {
        var result: CFTypeRef?
        let status = withQuery(accountID) { query in
            var lookup = query
            lookup[kSecReturnData] = true
            lookup[kSecMatchLimit] = kSecMatchLimitOne
            return SecItemCopyMatching(lookup as CFDictionary, &result)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(TokenPair.self, from: data)
    }

    static func delete(for accountID: String) throws {
        let status = withQuery(accountID) { SecItemDelete($0 as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    /// The data-protection Keychain reads without a prompt but needs a stable
    /// signing identity, which ad-hoc builds don't have. Probe once, then use
    /// the same answer everywhere: mixing the two writes to one Keychain and
    /// reads from the other.
    private static let usesDataProtectionKeychain: Bool = {
        let probe: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "__keychain_probe__",
            kSecValueData: Data("probe".utf8),
            kSecUseDataProtectionKeychain: true
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return false }

        var cleanup = probe
        cleanup.removeValue(forKey: kSecValueData)
        SecItemDelete(cleanup as CFDictionary)
        return true
    }()

    private static func withQuery(_ accountID: String,
                                  _ body: ([CFString: Any]) -> OSStatus) -> OSStatus {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountID
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain] = true
        }
        return body(query)
    }
}
