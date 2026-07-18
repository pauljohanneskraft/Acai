import Testing
@testable import AcaiCore

@Suite("Core: Feature-Envy Delegation (#111)")
struct FeatureEnvyDelegationTests {

    /// ACCEPTED PRECISION TRADEOFF (issue #111): an own-field read counts toward "own" — including the
    /// receiver identifier of a delegated call, since `ledger.credit()` records a bare read of the
    /// `ledger` field. So a method that only delegates through its own field scores own == foreign and
    /// is *not* flagged envious. Pinned deliberately; ``LcomAnalysis`` relies on the same read capture,
    /// where linking the two methods by the shared `ledger` field is correct.
    @Test func delegatingThroughAnOwnFieldCountsAsOwnInterest() {
        let ledger = TypeDeclaration(
            id: "Ledger", name: "Ledger", qualifiedName: "Ledger", kind: .class, accessLevel: .public,
            members: [Member(name: "credit", kind: .method, accessLevel: .public)],
            location: SourceLocation(filePath: "Sources/App/Ledger.swift", line: 1, column: 1))
        let clerk = TypeDeclaration(
            id: "Clerk", name: "Clerk", qualifiedName: "Clerk", kind: .class, accessLevel: .public,
            members: [
                Member(name: "ledger", kind: .property, accessLevel: .private),
                Member(name: "post", kind: .method, accessLevel: .public,
                       callSites: [CallSite(receiver: .type("Ledger"), methodName: "credit")],
                       fieldReads: [FieldAccess(name: "ledger")])
            ],
            location: SourceLocation(filePath: "Sources/App/Clerk.swift", line: 1, column: 1))
        let m = CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [ledger, clerk])
            .enriched().computeMetrics().types.first { $0.name == "Clerk" }
        #expect(m?.featureEnvyMethods == 0)
    }
}
