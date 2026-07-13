@preconcurrency import SwiftTreeSitter

/// Wraps `SwiftTreeSitter.Parser` set up for one grammar. Owns the compiled `Language`; carries no
/// language-specific logic of its own.
public struct SourceFileParser: Sendable {
    private let language: Language

    public init(language: Language) {
        self.language = language
    }

    /// Parses `source` into a `ParsedSource`, or `nil` when the grammar can't be loaded for this
    /// runtime (an ABI mismatch — a packaging error, not something a malformed source file can
    /// trigger) or the parse produces no tree at all.
    public func parse(source: String, fileName: String) -> ParsedSource? {
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil,
              let mutableTree = parser.parse(source)
        else { return nil }
        return ParsedSource(mutableTree: mutableTree, text: source, fileName: fileName)
    }
}
