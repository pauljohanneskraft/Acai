import Foundation

/// The single source of truth for GitHub sign-in state, instantiated once in `AcaiRootScene` and
/// injected into both the main `WindowGroup` and macOS's `Settings` scene — a `Settings` scene is a
/// separate `Scene`, not reachable from a `@StateObject` living on `ProjectBrowserView`, so this has
/// to be its own shared object rather than something the browser view owns (see this type's own
/// `AcaiRootScene` wiring). `NewCodebaseSheet`'s "From GitHub" tab reads `account` from here instead
/// of loading its own copy, so signing in/out in Settings is immediately reflected there too.
///
/// Holds the account **in memory only** — persistence stays exactly `GitHubTokenStore`'s existing
/// Keychain (or UI-test fixture file) round trip; this type never mirrors the credential or its
/// scopes into `UserDefaults`/`@AppStorage`, which would be a real security regression to check
/// for on every change that touches how the account is stored.
@MainActor
final class GitHubAccountStore: ObservableObject {
    @Published private(set) var account: GitHubTokenStore.StoredAccount?
    /// How many codebases (across every project) are GitHub-sourced — "Used by N codebases" in the
    /// signed-in view, so signing out has a legible consequence instead of being a leap in the dark.
    /// Refreshed on demand (`refreshCodebaseCount()`) rather than kept live-synced against
    /// `ProjectStore`, which this object has no reference to — see that method's own doc comment.
    @Published private(set) var codebaseCount: Int = 0
    /// Set while a scope/expiry refresh is in flight, so the Settings pane can show a loading state
    /// instead of a stale checklist with no indication it might be out of date.
    @Published private(set) var isRefreshingScopes = false

    private let tokenStore = GitHubTokenStore()
    private let service: GitHubAccountService

    init(service: GitHubAccountService? = nil) {
        self.service = service ?? (UITestFixtureResolver().resolveBaseDir() != nil
            ? FixtureGitHubAccountService() : LiveGitHubAccountService())
        self.account = tokenStore.load()
    }

    /// Persists a freshly-signed-in account (Keychain, via `GitHubTokenStore`) and publishes it.
    func signIn(_ account: GitHubTokenStore.StoredAccount) throws {
        try tokenStore.save(account)
        self.account = account
    }

    /// Resolves `credential` into a signed-in account (fetching the user + scope/expiry metadata)
    /// and persists it — the one place `GitHubAccountSection`'s two sign-in paths (PAT paste, device
    /// flow) both funnel through, so this store stays the single source of truth for what "signed
    /// in" means rather than the view assembling a `StoredAccount` itself.
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

    /// Passthrough to the underlying `GitHubAccountService`'s device-flow start — kept here (rather
    /// than exposing `service` itself) so `GitHubAccountSection` only ever talks to this store, never
    /// picks its own service instance.
    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceAuthFlow.DeviceCode {
        try await service.requestDeviceCode(clientID: clientID)
    }

    func pollForCredential(
        _ deviceCode: GitHubDeviceAuthFlow.DeviceCode, clientID: String
    ) async throws -> GitHubCredential {
        try await service.pollForCredential(deviceCode, clientID: clientID)
    }

    /// Re-fetches the signed-in user plus the token-metadata headers (the scope checklist, the
    /// expiry prompt) and updates the stored account with whatever GitHub reports now — used both
    /// right after sign-in and from a manual "Refresh" action, since a token's scopes/expiry can
    /// change server-side (a re-authorization, an App permission edit) without Acai's copy noticing
    /// until it asks again.
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
            // clearing them — a transient network hiccup shouldn't make an already-working feature
            // suddenly look ungated, nor make a working one look broken.
        }
    }

    /// A device-flow (`GitHubCredential.gitHubApp`) token already carries its own expiry; a PAT's
    /// only comes from the response header `refreshScopes()` reads, so `info.tokenExpiresAt` wins
    /// when present and this is the fallback.
    private func credentialExpiresAt(_ credential: GitHubCredential) -> Date? {
        if case .gitHubApp(_, let expiresAt, _) = credential { return expiresAt }
        return nil
    }

    /// Counts GitHub-sourced codebases by reading a **fresh** `ProjectStore` snapshot from disk,
    /// rather than holding a live reference to the one `ProjectBrowserViewModel` owns — this object
    /// is shared with the `Settings` scene, which has no access to that view model's instance (see
    /// this type's own doc comment), and `ProjectStore.load()` isn't safe to call twice on one
    /// instance (it appends rather than replacing). A fresh instance is cheap enough for an
    /// occasionally-viewed count and reflects state as of the last save, which is what "Used by N
    /// codebases" needs — not a live subscription.
    func refreshCodebaseCount() {
        let store = ProjectStore()
        codebaseCount = store.projects.flatMap(\.codebases).filter { $0.githubSource != nil }.count
    }
}
