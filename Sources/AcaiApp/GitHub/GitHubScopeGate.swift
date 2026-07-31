import SwiftUI

/// A named GitHub token scope one of Acai's features can require. Not exhaustive of every scope
/// GitHub defines — just the ones some feature in this app actually cares about, extended as new
/// features need more (see `GitHubScopeGate`'s doc comment for the concrete planned consumer).
struct GitHubScope: Hashable, Sendable {
    var rawValue: String
    var displayName: String

    static let contentsRead = GitHubScope(rawValue: "contents:read", displayName: "Contents")
    static let metadataRead = GitHubScope(rawValue: "metadata:read", displayName: "Metadata")
    /// Not required by anything shipped yet — a future PR picker feature is the concrete planned
    /// consumer, which is exactly why this mechanism exists *before* that feature does: so the
    /// picker can gray itself out with a clear explanation on day one instead of failing opaquely
    /// mid-flow the first time someone's token lacks it.
    static let pullRequestsRead = GitHubScope(rawValue: "pull_requests:read", displayName: "Pull Requests")
}

/// A generic "does the signed-in token have what a feature needs" primitive — a value you
/// construct with the scopes a feature requires and ask `status(given:)` about, rather than a
/// namespaced static-check function. Built now even though nothing in the app currently consumes
/// it for real: this is the mechanism itself, not a feature to gate with it, since the concrete
/// consumer (a future PR picker, `pull_requests:read`) is separate, not-yet-built work that
/// depends on this existing first.
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

    /// `accountScopes` is `GitHubTokenStore.StoredAccount.scopes` — `nil` means "unknown" (see that
    /// property's own doc comment), distinct from `[]` ("confirmed to have none").
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
            // Phrased to avoid needing to pluralize "scope" (no manual "(s)" suffixing) rather
            // than counting how many are missing.
            "Your current token is missing: " + scopes.map(\.displayName).joined(separator: ", ") + "."
        case .unknown:
            "Acai couldn't confirm which scopes your token has. Re-authorize to check again."
        }
    }
}
