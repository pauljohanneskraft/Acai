import Testing
import AcaiCore
import AcaiTreeSitter
import TreeSitterC
import AcaiCFamily

/// `TreeSitterGrammar.parse` attaches the tree's own `ERROR`/missing-node diagnostics to whatever the
/// extractor returned. An extractor that recorded a diagnostic of its own must keep it.
@Suite("Tree-sitter grammar diagnostics")
struct TreeSitterGrammarDiagnosticTests {

    private let grammar = TreeSitterGrammar(
        language: Language(language: tree_sitter_c()), sourceLanguage: .c)

    private func extractorDiagnostic(_ fileName: String) -> ParseDiagnostic {
        ParseDiagnostic(
            location: SourceLocation(filePath: fileName, line: 7, column: 3),
            kind: .unresolvedReference,
            message: "from the extractor"
        )
    }

    private func artifact(_ fileName: String, carrying diagnostics: [ParseDiagnostic]) -> CodeArtifact {
        CodeArtifact(metadata: .init(
            sourceLanguage: .c, filePaths: [fileName], parseDiagnostics: diagnostics))
    }

    @Test func anExtractorsDiagnosticSurvivesAMalformedParse() {
        let fileName = "broken.c"
        let artifact = grammar.parse(source: "struct Widget { int", fileName: fileName) { _ in
            self.artifact(fileName, carrying: [self.extractorDiagnostic(fileName)])
        }

        let diagnostics = artifact.metadata.parseDiagnostics
        #expect(diagnostics.first == extractorDiagnostic(fileName))
        #expect(diagnostics.count > 1)
        #expect(diagnostics.dropFirst().allSatisfy { $0.kind == .error || $0.kind == .missing })
    }

    @Test func aCleanParseKeepsOnlyTheExtractorsDiagnostics() {
        let fileName = "clean.c"
        let artifact = grammar.parse(source: "struct Widget { int value; };", fileName: fileName) { _ in
            self.artifact(fileName, carrying: [self.extractorDiagnostic(fileName)])
        }

        #expect(artifact.metadata.parseDiagnostics == [extractorDiagnostic(fileName)])
    }
}
