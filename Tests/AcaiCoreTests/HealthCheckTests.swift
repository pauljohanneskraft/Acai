import Testing
import Foundation
@testable import AcaiCore

/// Covers `HealthCheck`: a clean artifact scores 1.0; diagnostics lower the score, are counted by
/// kind, and are sorted by location.
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
}
