import Foundation
import Security

/// Keychain-backed storage for the signed-in GitHub account's credential + display info, shared
/// verbatim between macOS and iOS — Keychain access to an app's own items doesn't require the
/// sandbox entitlement on either platform, unlike the filesystem bookmarks `ScopedResourceAccess`
/// needs. Only one account is ever stored at a time (`account`), matching the single "GitHub
/// sign-in" the app exposes.
struct GitHubTokenStore {
    private let service = "de.kraftsoftware.Acai.github"
    private let account = "default"

    /// The signed-in account: its credential plus enough profile info to show who's signed in.
    struct StoredAccount: Codable, Hashable {
        var credential: GitHubCredential
        var login: String
        var avatarURL: URL?
    }

    enum Failure: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                "Keychain error \(status)."
            }
        }
    }

    /// The stored account, if any. `nil` both when nothing was ever saved and when the stored
    /// item can no longer be decoded (treated as "signed out" rather than surfaced as an error).
    func load() -> StoredAccount? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredAccount.self, from: data)
    }

    /// Saves (inserting or overwriting) the signed-in account.
    func save(_ account: StoredAccount) throws {
        let data = try JSONEncoder().encode(account)
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let attributes = [kSecValueData as String: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes)
            guard updateStatus == errSecSuccess else { throw Failure.keychain(updateStatus) }
        } else if addStatus != errSecSuccess {
            throw Failure.keychain(addStatus)
        }
    }

    /// Signs out: removes the stored account. Already-cloned folders on disk are untouched —
    /// they remain plain local codebases; further `pull`s against private repos will fail until
    /// signing back in.
    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
