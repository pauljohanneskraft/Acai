import SwiftUI

struct GitHubScope: Hashable, Sendable {
    var rawValue: String
    var displayName: String

    static let contentsRead = GitHubScope(rawValue: "contents:read", displayName: "Contents")
    static let metadataRead = GitHubScope(rawValue: "metadata:read", displayName: "Metadata")
    /// Not required by anything shipped yet — the future PR picker feature is the planned consumer.
    static let pullRequestsRead = GitHubScope(rawValue: "pull_requests:read", displayName: "Pull Requests")
}

/// A value you construct with the scopes a feature requires and ask `status(given:)` about.
struct GitHubScopeGate {
    var required: [GitHubScope]

    enum Status: Equatable {
        case satisfied
        case missing([GitHubScope])
        /// The signed-in token's scopes aren't known — e.g. a fine-grained PAT, which doesn't
        /// currently report scopes via any response header. Treated conservatively as "can't
        /// confirm this works," never silently upgraded to `.satisfied`.
        case unknown
    }

    /// `accountScopes` is `GitHubTokenStore.StoredAccount.scopes` — `nil` means "unknown", distinct
    /// from `[]` ("confirmed to have none").
    func status(given accountScopes: [String]?) -> Status {
        guard let accountScopes else { return .unknown }
        let missing = required.filter { !accountScopes.contains($0.rawValue) }
        return missing.isEmpty ? .satisfied : .missing(missing)
    }
}

extension View {
    /// Grays out `self` (rather than hiding it) when `gate` isn't satisfied by `accountScopes`,
    /// with a tap-through explanation of exactly which scope is missing and a direct
    /// "Re-authorize" path — never a feature that just silently doesn't work.
    func scopeGated(
        _ gate: GitHubScopeGate, accountScopes: [String]?, onReauthorize: @escaping () -> Void
    ) -> some View {
        modifier(GitHubScopeGateModifier(gate: gate, accountScopes: accountScopes, onReauthorize: onReauthorize))
    }
}

private struct GitHubScopeGateModifier: ViewModifier {
    let gate: GitHubScopeGate
    let accountScopes: [String]?
    let onReauthorize: () -> Void
    @State private var showExplanation = false

    private var status: GitHubScopeGate.Status { gate.status(given: accountScopes) }

    func body(content: Content) -> some View {
        switch status {
        case .satisfied:
            content
        case .missing, .unknown:
            content
                .disabled(true)
                .opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { showExplanation = true }
                .popover(isPresented: $showExplanation) { explanation }
                .accessibilityIdentifier("scopeGate.disabledOverlay")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(explanationText)
            Button("Re-authorize") {
                showExplanation = false
                onReauthorize()
            }
            .accessibilityIdentifier("scopeGate.reauthorizeButton")
        }
        .padding()
        .frame(maxWidth: 280)
    }

    private var explanationText: String {
        switch status {
        case .satisfied:
            ""
        case .missing(let scopes):
            "Your current token is missing: " + scopes.map(\.displayName).joined(separator: ", ") + "."
        case .unknown:
            "Acai couldn't confirm which scopes your token has. Re-authorize to check again."
        }
    }
}
