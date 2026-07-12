import Foundation
import Testing
import UMLCore
@testable import UMLApp

/// Regression coverage for the "Nesting Depth reads 0" bug: the app used to persist the
/// display-*flattened* artifact and then compute metrics on it, so `nestingDepth` (which reads the
/// nested-type tree) collapsed to 0 for every type. The fix stores the un-flattened **semantic**
/// artifact and flattens only for display via ``CodebaseAnalyzer/flattenedForDisplay(_:)``.
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

        // The stored *semantic* artifact keeps the nested-type tree, so metrics see Outer → Inner.
        let semanticMax = semantic.computeMetrics().types.map(\.nestingDepth).max() ?? 0
        #expect(semanticMax == 1)

        // The display flatten hoists `Inner` to the top level with a qualified name — this is the
        // pre-fix stored form, and exactly why nesting used to read 0.
        let display = CodebaseAnalyzer().flattenedForDisplay(semantic)
        #expect(display.types.count == 2)
        #expect(display.types.contains { $0.name == "Outer.Inner" })
        let displayMax = display.computeMetrics().types.map(\.nestingDepth).max() ?? 0
        #expect(displayMax == 0)
    }
}
