/// A language's documentation convention: which markers single a comment out as documentation, and
/// how to strip them so what is stored reads as prose.
///
/// Parsers own the convention data (`///` and `/**` in one language, `/*!` in another, a string
/// literal in the declaration's body in a third) and hand the engine the prose; the engine never
/// learns which language spells it which way.
public struct DocumentationComment: Sendable, Equatable, Hashable {
    /// Line-comment prefixes that mark the line as documentation, e.g. `///` or `//!`.
    public var linePrefixes: [String]
    /// Block-comment openings that mark the block as documentation, e.g. `/**` or `/*!`.
    public var blockOpenings: [String]
    /// The terminator closing a documentation block.
    public var blockClosing: String
    /// Decoration a documentation block repeats on its continuation lines, e.g. `*`.
    public var continuationMarker: String?
    /// Delimiters of a string literal that is itself the documentation, longest first, e.g. `"""`.
    public var literalDelimiters: [String]

    public init(
        linePrefixes: [String] = [],
        blockOpenings: [String] = [],
        blockClosing: String = "*/",
        continuationMarker: String? = "*",
        literalDelimiters: [String] = []
    ) {
        self.linePrefixes = linePrefixes
        self.blockOpenings = blockOpenings
        self.blockClosing = blockClosing
        self.continuationMarker = continuationMarker
        self.literalDelimiters = literalDelimiters
    }

    /// The prose documented by the comments written immediately above one declaration, in source
    /// order, each the verbatim comment text.
    ///
    /// `nil` unless the comment nearest the declaration is documentation: a plain comment sitting
    /// between the two detaches whatever is above it, so an unrelated note is never mistaken for
    /// documentation.
    public func prose(fromLeading comments: [String]) -> String? {
        var lines: [String] = []
        for comment in comments.reversed() {
            guard let stripped = strippedLines(of: comment) else { break }
            lines = stripped + lines
        }
        return prose(of: lines)
    }

    /// The prose inside a string literal serving as a declaration's documentation — quotes, and any
    /// prefix in front of them, removed.
    ///
    /// The opening delimiter indents the line it shares, so that line's own indentation is dropped
    /// and the shared indentation is measured from the lines below it.
    public func prose(fromLiteral literal: String) -> String? {
        for delimiter in literalDelimiters {
            guard let opening = literal.range(of: delimiter) else { continue }
            var body = literal[opening.upperBound...]
            if body.hasSuffix(delimiter) {
                body = body.dropLast(delimiter.count)
            }
            var lines = body.components(separatedBy: "\n").map { $0.trimmingTrailingWhitespace() }
            let first = lines.isEmpty ? "" : String(lines.removeFirst().drop(while: \.isHorizontalWhitespace))
            return prose(of: [first] + dedented(lines))
        }
        return nil
    }

    // MARK: - Markers

    /// `nil` when `comment` carries no documentation marker, so the caller stops looking further up.
    private func strippedLines(of comment: String) -> [String]? {
        let text = comment.trimmingTrailingWhitespace()
        if let opening = blockOpenings.sorted(by: { $0.count > $1.count }).first(where: {
            text.hasPrefix($0) && text.count >= $0.count + blockClosing.count
        }) {
            return blockLines(of: text, opening: opening)
        }
        if let prefix = linePrefixes.sorted(by: { $0.count > $1.count }).first(where: text.hasPrefix) {
            return [String(text.dropFirst(prefix.count)).droppingLeadingSpace()]
        }
        return nil
    }

    private func blockLines(of text: String, opening: String) -> [String] {
        var body = text.dropFirst(opening.count)
        if body.hasSuffix(blockClosing) {
            body = body.dropLast(blockClosing.count)
        }
        return body.components(separatedBy: "\n").map { line in
            guard let marker = continuationMarker else { return line }
            let indented = line.drop(while: \.isHorizontalWhitespace)
            guard indented.hasPrefix(marker) else { return line }
            return String(indented.dropFirst(marker.count)).droppingLeadingSpace()
        }
    }

    // MARK: - Prose

    /// Blank edges and the indentation every line shares removed, so the text reads as prose rather
    /// than as a fragment of the source it was lifted from. `nil` when nothing is left.
    private func prose(of lines: [String]) -> String? {
        var trimmed = dedented(lines.map { $0.trimmingTrailingWhitespace() })
        while trimmed.first?.isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.isEmpty == true { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed.joined(separator: "\n")
    }

    /// `lines` with the indentation all of them share removed; a blank line counts for nothing.
    private func dedented(_ lines: [String]) -> [String] {
        let indentation = lines.filter { !$0.isEmpty }
            .map { $0.prefix(while: \.isHorizontalWhitespace).count }
            .min() ?? 0
        return lines.map { String($0.dropFirst(min(indentation, $0.count))) }
    }
}

extension Character {
    fileprivate var isHorizontalWhitespace: Bool { self == " " || self == "\t" }
}

extension StringProtocol {
    fileprivate func trimmingTrailingWhitespace() -> String {
        var text = String(self)
        while let last = text.last, last.isHorizontalWhitespace || last == "\r" {
            text.removeLast()
        }
        return text
    }

    fileprivate func droppingLeadingSpace() -> String {
        first == " " ? String(dropFirst()) : String(self)
    }
}
