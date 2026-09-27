import AcaiCore

/// A loaded Tree-sitter grammar and the parse pipeline every plugin runs it through. A parser holds
/// one as a `let`, so the grammar is loaded once per run rather than once per file.
///
/// `setLanguage` only fails on an ABI mismatch with the linked `SwiftTreeSitter` runtime — a
/// build/packaging error, not something a malformed source file can trigger. Rather than `try!` and
/// crash, this degrades to an empty artifact carrying a parse diagnostic.
public struct TreeSitterGrammar: Sendable {
    public let language: Language
    public let sourceLanguage: CodeArtifact.SourceLanguage

    public init(language: Language, sourceLanguage: CodeArtifact.SourceLanguage) {
        self.language = language
        self.sourceLanguage = sourceLanguage
    }

    public func makeParser() -> Parser? {
        let parser = Parser()
        do {
            try parser.setLanguage(language)
            return parser
        } catch {
            return nil
        }
    }

    public func loadFailureArtifact(fileName: String) -> CodeArtifact {
        CodeArtifact(metadata: .init(
            sourceLanguage: sourceLanguage,
            filePaths: [fileName],
            parseDiagnostics: [ParseDiagnostic(
                location: SourceLocation(filePath: fileName, line: 1, column: 1),
                kind: .error,
                message: "Failed to load the \(sourceLanguage.rawValue) tree-sitter grammar."
            )]
        ))
    }

    /// Parses `source` and hands the tree's root to `extract`, which builds the artifact; a tree
    /// that could not be produced yields an empty artifact, and a best-effort tree with `ERROR` or
    /// missing nodes gets its concrete parse diagnostics attached so partial output is flagged.
    public func parse(
        source: String, fileName: String, extract: (Node) -> CodeArtifact
    ) -> CodeArtifact {
        guard let parser = makeParser() else {
            return loadFailureArtifact(fileName: fileName)
        }
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            return CodeArtifact(metadata: .init(sourceLanguage: sourceLanguage, filePaths: [fileName]))
        }
        var artifact = extract(root)
        if root.hasError {
            artifact.metadata.parseDiagnostics = ParseDiagnosticsCollector(
                context: SourceFileContext(source: source, fileName: fileName)
            ).diagnostics(in: root)
        }
        return artifact
    }
}
