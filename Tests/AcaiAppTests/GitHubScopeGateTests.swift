import Testing
@testable import AcaiApp

/// A generic scope-gating primitive: `GitHubScopeGate.status(given:)` is the whole decision —
/// unit-tested directly here even though nothing in the app consumes it for a real feature yet
/// (see `GitHubScopeGate`'s own doc comment for why that's a deliberate scoping decision).
@Suite("GitHubScopeGate")
struct GitHubScopeGateTests {
    private let gate = GitHubScopeGate(required: [.contentsRead, .pullRequestsRead])

    @Test func satisfiedWhenAllRequiredScopesPresent() {
        let status = gate.status(given: ["contents:read", "pull_requests:read", "metadata:read"])
        #expect(status == .satisfied)
    }

    @Test func missingListsExactlyTheAbsentScopes() {
        let status = gate.status(given: ["contents:read"])
        #expect(status == .missing([.pullRequestsRead]))
    }

    @Test func missingListsAllRequiredScopesWhenNoneArePresent() {
        let status = gate.status(given: [])
        #expect(status == .missing([.contentsRead, .pullRequestsRead]))
    }

    @Test func nilScopesAreUnknownNotSatisfied() {
        // `nil` (a fine-grained PAT, which doesn't currently report scopes) must never be silently
        // treated as "has everything" — that would defeat the whole point of the gate.
        let status = gate.status(given: nil)
        #expect(status == .unknown)
    }
}
