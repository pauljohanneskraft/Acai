import Foundation
import Security

/// Keychain-backed storage for the signed-in GitHub account's credential + display info, shared
/// verbatim between macOS and iOS — unlike the filesystem bookmarks `ScopedResourceAccess` needs,
/// Keychain access to an app's own items requires no sandbox entitlement. Only one account is
/// ever stored at a time, matching the single "GitHub sign-in" the app exposes.
struct GitHubTokenStore {
    private let service = "de.kraftsoftware.Acai.github"
    private let account = "default"

    /// XCUITest bundles run with `CODE_SIGNING_ALLOWED=NO`, so they lack a keychain-access-group
    /// entitlement and `SecItemAdd`/`SecItemUpdate` fail with `errSecMissingEntitlement` (-34018).
    /// When a UI-test fixture is active, storage redirects to a plain JSON file under the
    /// fixture's disposable directory instead. `resolveBaseDir()` is `nil` for every real user
    /// launch, so a real credential can never land in a plain file.
    private var fixtureFileURL: URL? {
        UITestFixtureResolver().resolveBaseDir()?.appendingPathComponent("github-token.json")
    }

    /// The signed-in account: its credential plus enough profile info to show who's signed in.
    struct StoredAccount: Codable, Hashable {
        var credential: GitHubCredential
        var login: String
        var avatarURL: URL?
        /// The scopes GitHub reported the current token actually has (the scope checklist), read from
        /// the `X-OAuth-Scopes` response header at sign-in time — classic PATs and OAuth/device-flow
        /// tokens report this; fine-grained PATs currently don't, so `nil` there means "unknown,"
        /// distinct from `[]` ("confirmed to have none"). `[String]?` (not defaulted in this
        /// `Codable` struct's synthesized `init(from:)`) decodes to `nil` for every account already
        /// persisted before this field existed — see `GitHubTokenStoreMigrationTests` for the proof,
        /// not just the reasoning.
        var scopes: [String]?
        /// When the current token expires, if known — a device-flow (`GitHubCredential.gitHubApp`)
        /// token already carries this; a fine-grained PAT's `github-authentication-token-expiration`
        /// response header is captured here too, when GitHub sends it. `nil` means "no known expiry"
        /// (a classic PAT, or a fine-grained PAT whose expiry wasn't reported).
        var tokenExpiresAt: Date?
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
        if let fixtureFileURL {
            guard let data = try? Data(contentsOf: fixtureFileURL) else { return nil }
            return try? JSONDecoder().decode(StoredAccount.self, from: data)
        }

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
        if let fixtureFileURL {
            let data = try JSONEncoder().encode(account)
            try data.write(to: fixtureFileURL, options: .atomic)
            return
        }

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
        if let fixtureFileURL {
            try? FileManager.default.removeItem(at: fixtureFileURL)
            return
        }
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
