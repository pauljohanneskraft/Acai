import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Regression coverage: persisting the display-*flattened* artifact made `nestingDepth` (which
/// reads the nested-type tree) collapse to 0. Fix stores the un-flattened **semantic** artifact
/// and flattens only for display via ``CodebaseAnalyzer/flattenedForDisplay(_:)``.
@Suite("App: Nesting depth survives storage")
struct CodebaseAnalyzerNestingTests {

    /// `Outer { Inner }` — one level of type nesting.
    private func nestedArtifact() -> CodeArtifact {
        let inner = TypeDeclaration(
            id: "Outer.Inner", name: "Inner", qualifiedName: "Outer.Inner", kind: .struct,
            accessLevel: .internal,
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 2, column: 5))
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .struct,
            accessLevel: .internal, nestedTypes: [inner],
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 1, column: 1))
        return CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [outer], relationships: [])
    }

    @Test func semanticArtifactPreservesNestingWhileDisplayFlattensToZero() {
        let semantic = nestedArtifact()

        // Semantic artifact keeps the nested-type tree, so metrics see Outer → Inner.
        let semanticMax = semantic.computeMetrics().types.map(\.nestingDepth).max() ?? 0
        #expect(semanticMax == 1)

        // Display flatten hoists `Inner` to the top level — the pre-fix stored form.
        let display = CodebaseAnalyzer().flattenedForDisplay(semantic)
        #expect(display.types.count == 2)
        #expect(display.types.contains { $0.name == "Outer.Inner" })
        let displayMax = display.computeMetrics().types.map(\.nestingDepth).max() ?? 0
        #expect(displayMax == 0)
    }
}
