import Foundation

/// The registered GitHub App's client ID, used by `GitHubDeviceAuthFlow` for sign-in — a value you
/// read from `.standard`, not a namespace, matching `AcaiConstants.standard`'s shape.
///
/// One-time manual setup, done once in your own GitHub account (this can't be automated — it
/// requires an interactive GitHub login):
/// 1. Register a GitHub App at https://github.com/settings/apps/new.
/// 2. Under "Repository permissions", set `Contents: Read-only` and `Metadata: Read-only` — no
///    other permissions. This is what makes GitHub access read-only at the token level, not just
///    by app-side convention.
/// 3. Under "Optional features", enable "Device Flow". No webhook or callback URL is needed.
/// 4. Opt out of user-token expiration there — tokens are used as-is with no refresh mechanism,
///    so an expiring token would eventually make every GitHub operation fail until the user signs
///    in again.
/// 5. Paste the App's Client ID below. Users additionally "install" the App on whichever
///    repositories/orgs they want to grant it access to — a separate one-time step on github.com,
///    distinct from sign-in, done per account/org rather than per device.
struct GitHubAppConfiguration: Sendable {
    static let standard = GitHubAppConfiguration(clientID: "Iv23liXDANpxcaVNAO4c")

    let clientID: String
}
