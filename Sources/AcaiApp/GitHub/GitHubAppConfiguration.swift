import Foundation

/// The registered GitHub App's client ID, used by `GitHubDeviceAuthFlow` for sign-in.
///
/// One-time manual setup on github.com (requires an interactive login, can't be automated):
/// 1. Register a GitHub App at https://github.com/settings/apps/new.
/// 2. Under "Repository permissions", set `Contents: Read-only` and `Metadata: Read-only` only —
///    this is what makes access read-only at the token level, not just app-side convention.
/// 3. Under "Optional features", enable "Device Flow". No webhook or callback URL needed.
/// 4. Opt out of user-token expiration — tokens are used as-is with no refresh mechanism.
/// 5. Paste the App's Client ID below. Users must separately "install" the App on whichever
///    repositories/orgs they want to grant it access to.
struct GitHubAppConfiguration: Sendable {
    static let standard = GitHubAppConfiguration(clientID: "Iv23liXDANpxcaVNAO4c")

    let clientID: String
}
