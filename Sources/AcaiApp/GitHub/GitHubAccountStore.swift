import Foundation

/// The single source of truth for GitHub sign-in state, shared between the main `WindowGroup` and
/// macOS's `Settings` scene.
///
/// Holds the account **in memory only** — persistence stays exactly `GitHubTokenStore`'s existing
/// Keychain (or UI-test fixture file) round trip; this type never mirrors the credential or its
/// scopes into `UserDefaults`/`@AppStorage`.
@MainActor
final class GitHubAccountStore: ObservableObject {
    @Published private(set) var account: GitHubTokenStore.StoredAccount?
    /// "Used by N codebases" in the signed-in view. Refreshed on demand (`refreshCodebaseCount()`)
    /// rather than kept live-synced against `ProjectStore`, which this object has no reference to.
    @Published private(set) var codebaseCount: Int = 0
    @Published private(set) var isRefreshingScopes = false

    private let tokenStore = GitHubTokenStore()
    private let service: GitHubAccountService

    init(service: GitHubAccountService? = nil) {
        self.service = service ?? (UITestFixtureResolver().resolveBaseDir() != nil
            ? FixtureGitHubAccountService() : LiveGitHubAccountService())
        self.account = tokenStore.load()
    }

    func signIn(_ account: GitHubTokenStore.StoredAccount) throws {
        try tokenStore.save(account)
        self.account = account
    }

    /// Resolves `credential` into a signed-in account (fetching the user + scope/expiry metadata)
    /// and persists it — the one place `GitHubAccountSection`'s two sign-in paths (PAT paste, device
    /// flow) both funnel through.
    func signIn(with credential: GitHubCredential) async throws {
        let info = try await service.authenticatedUserInfo(credential: credential)
        let stored = GitHubTokenStore.StoredAccount(
            credential: credential, login: info.user.login, avatarURL: info.user.avatarURL,
            scopes: info.scopes, tokenExpiresAt: info.tokenExpiresAt ?? credentialExpiresAt(credential))
        try signIn(stored)
    }

    func signOut() {
        tokenStore.clear()
        account = nil
    }

    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode {
        try await service.requestDeviceCode(clientID: clientID)
    }

    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential {
        try await service.pollForCredential(deviceCode, clientID: clientID)
    }

    /// Re-fetches the signed-in user plus token metadata and updates the stored account — a token's
    /// scopes/expiry can change server-side without Acai's copy noticing until it asks again.
    func refreshScopes() async {
        guard let account else { return }
        isRefreshingScopes = true
        defer { isRefreshingScopes = false }
        do {
            let info = try await service.authenticatedUserInfo(credential: account.credential)
            var updated = account
            updated.scopes = info.scopes
            updated.tokenExpiresAt = info.tokenExpiresAt ?? credentialExpiresAt(account.credential)
            try tokenStore.save(updated)
            self.account = updated
        } catch {
            // A failed refresh leaves the previously-known scopes/expiry in place rather than
            // clearing them — a transient network hiccup shouldn't make a working feature look broken.
        }
    }

    /// A device-flow (`GitHubCredential.gitHubApp`) token already carries its own expiry; a PAT's
    /// only comes from the response header `refreshScopes()` reads, so `info.tokenExpiresAt` wins
    /// when present and this is the fallback.
    private func credentialExpiresAt(_ credential: GitHubCredential) -> Date? {
        if case .gitHubApp(_, let expiresAt, _) = credential { return expiresAt }
        return nil
    }

    /// Reads a **fresh** `ProjectStore` snapshot from disk rather than holding a live reference —
    /// `ProjectStore.load()` isn't safe to call twice on one instance (it appends, not replaces).
    func refreshCodebaseCount() {
        let store = ProjectStore()
        codebaseCount = store.projects.flatMap(\.codebases).filter { $0.githubSource != nil }.count
    }
}
