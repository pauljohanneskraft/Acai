import SwiftUI

struct GitHubScope: Hashable, Sendable {
    var rawValue: String
    var displayName: LocalizedStringResource

    static func == (lhs: GitHubScope, rhs: GitHubScope) -> Bool { lhs.rawValue == rhs.rawValue }

    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    static let contentsRead = GitHubScope(rawValue: "contents:read", displayName: .app("GitHubScope.ContentsRead"))
    static let metadataRead = GitHubScope(rawValue: "metadata:read", displayName: .app("GitHubScope.MetadataRead"))
    /// Not required by anything shipped yet — the future PR picker feature is the planned consumer.
    static let pullRequestsRead = GitHubScope(
        rawValue: "pull_requests:read", displayName: .app("GitHubScope.PullRequestsRead"))
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
            Text(localized: explanationText)
            Button(.app("View.GitHubScopeGateModifier.ReAuthorize")) {
                showExplanation = false
                onReauthorize()
            }
            .accessibilityIdentifier("scopeGate.reauthorizeButton")
        }
        .padding()
        .frame(maxWidth: 280)
    }

    private var explanationText: LocalizedStringResource {
        switch status {
        case .satisfied:
            return ""
        case .missing(let scopes):
            let joined = scopes.map { String(localized: $0.displayName) }.joined(separator: ", ")
            return .app("View.GitHubScopeGateModifier.MissingScopes \(joined)")
        case .unknown:
            return .app("View.GitHubScopeGateModifier.UnknownScopes")
        }
    }
}
