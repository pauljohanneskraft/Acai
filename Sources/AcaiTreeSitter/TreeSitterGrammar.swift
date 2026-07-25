import AcaiCore

/// A tree-sitter grammar paired with the source language it represents.
///
/// `setLanguage` only fails on an ABI mismatch with the linked `SwiftTreeSitter` runtime — a
/// build/packaging error, not something a malformed source file can trigger. Rather than `try!` and
/// crash, this degrades to an empty artifact carrying a parse diagnostic.
public struct TreeSitterGrammar {
    public let language: Language
    public let sourceLanguage: CodeArtifact.SourceLanguage

    public init(language: Language, sourceLanguage: CodeArtifact.SourceLanguage) {
        self.language = language
        self.sourceLanguage = sourceLanguage
    }

    /// A parser configured with this grammar, or `nil` if the grammar could not be loaded.
    public func makeParser() -> Parser? {
        let parser = Parser()
        do {
            try parser.setLanguage(language)
            return parser
        } catch {
            return nil
        }
    }

    /// An empty artifact for `fileName` carrying a single diagnostic explaining that the grammar
    /// could not be loaded, so the failure surfaces in output instead of crashing the process.
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
}
