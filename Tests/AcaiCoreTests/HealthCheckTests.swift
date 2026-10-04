import Testing
import Foundation
@testable import AcaiCore

@Suite("Core: HealthCheck")
struct HealthCheckTests {

    private func type(_ name: String) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], diagnostics: [ParseDiagnostic]) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, parseDiagnostics: diagnostics), types: types)
    }

    @Test func cleanArtifactScoresPerfect() {
        let report = HealthCheck(artifact: artifact([type("A"), type("B")], diagnostics: [])).report
        #expect(report.score == 1)
        #expect(report.typeCount == 2)
        #expect(report.diagnosticCount == 0)
    }

    @Test func diagnosticsLowerScoreAndCountByKind() {
        let diagnostics = [
            ParseDiagnostic(
                location: SourceLocation(filePath: "B.swift", line: 9, column: 1),
                kind: .unresolvedReference, message: "unresolved Foo"),
            ParseDiagnostic(
                location: SourceLocation(filePath: "A.swift", line: 3, column: 1),
                kind: .unresolvedReference, message: "unresolved Bar")
        ]
        let report = HealthCheck(
            artifact: artifact([type("A"), type("B")], diagnostics: diagnostics)).report
        // 2 diagnostics / 2 types → penalty 1.0 → score 0.
        #expect(report.score == 0)
        #expect(report.diagnosticCount == 2)
        #expect(report.countsByKind["unresolvedReference"] == 2)
        // Sorted by file path then line.
        #expect(report.diagnostics.map(\.location.filePath) == ["A.swift", "B.swift"])
    }

    // MARK: - The scope the parse ran over

    private func root(_ path: String, _ detector: String, fallback: Bool = false) -> CodeArtifact.DiscoveredRoot {
        CodeArtifact.DiscoveredRoot(
            path: path, detector: detector, languages: [.swift],
            sourceDirs: ["\(path)/Sources"], isFallback: fallback)
    }

    private func artifact(roots: [CodeArtifact.DiscoveredRoot]) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, discoveredRoots: roots), types: [type("A")])
    }

    /// Without the roots, a folder analysing to fewer types than it contains has only its type count
    /// to look at — which is the complaint, not the answer.
    @Test func theReportCarriesTheDiscoveredRootsAsRecorded() {
        let roots = [root("app", "SwiftPackageManagerDetector"), root("web", "NodeDetector")]
        let report = HealthCheck(artifact: artifact(roots: roots)).report

        #expect(report.discoveredRoots == roots)
        #expect(report.discoveredRoots.map(\.sourceDirs) == [["app/Sources"], ["web/Sources"]])
    }

    @Test func everyRootComingFromTheFallbackIsReportedAsSuch() {
        let report = HealthCheck(artifact: artifact(roots: [root(".", "FallbackDetector", fallback: true)])).report

        #expect(report.isFallbackOnly)
    }

    /// One manifest-claimed root is enough: the folder was scoped by a build system somewhere, so the
    /// "nothing was recognised" message would be wrong.
    @Test func oneManifestClaimedRootMeansItIsNotFallbackOnly() {
        let roots = [root(".", "FallbackDetector", fallback: true), root("web", "NodeDetector")]
        let report = HealthCheck(artifact: artifact(roots: roots)).report

        #expect(!report.isFallbackOnly)
    }

    /// An artifact with no roots recorded at all (a single file parsed directly, or one written
    /// before roots were recorded) says nothing about build systems rather than claiming none.
    @Test func noRecordedRootsIsNotFallbackOnly() {
        let report = HealthCheck(artifact: artifact(roots: [])).report

        #expect(report.discoveredRoots.isEmpty)
        #expect(!report.isFallbackOnly)
    }

    @Test func incompleteDiscoveryIsReportedButNotScored() {
        let diagnostic = ParseDiagnostic(
            location: SourceLocation(filePath: "manifest", line: 1, column: 1),
            kind: .incompleteDiscovery, message: "manifest could not be read")
        let report = HealthCheck(artifact: artifact([type("A")], diagnostics: [diagnostic])).report
        #expect(report.score == 1)
        #expect(report.diagnosticCount == 1)
        #expect(report.countsByKind["incompleteDiscovery"] == 1)
    }
}
