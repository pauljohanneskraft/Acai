/// A language's documentation convention: which markers single a comment out as documentation, and
/// how to strip them so what is stored reads as prose.
///
/// Parsers own the convention data and hand the engine the prose; the engine never learns which
/// language spells it which way.
public struct DocumentationComment: Sendable, Equatable, Hashable {
    /// Line-comment prefixes that mark the line as documentation.
    public var linePrefixes: [String]
    /// Block-comment openings that mark the block as documentation.
    public var blockOpenings: [String]
    /// The terminator closing a documentation block.
    public var blockClosing: String?
    /// Decoration a documentation block repeats on its continuation lines.
    public var continuationMarker: String?
    /// Delimiters of a string literal that is itself the documentation.
    public var literalDelimiters: [String]

    public init(
        linePrefixes: [String] = [],
        blockOpenings: [String] = [],
        blockClosing: String? = nil,
        continuationMarker: String? = nil,
        literalDelimiters: [String] = []
    ) {
        self.linePrefixes = linePrefixes.sorted { $0.count > $1.count }
        self.blockOpenings = blockOpenings.sorted { $0.count > $1.count }
        self.blockClosing = blockClosing
        self.continuationMarker = continuationMarker
        self.literalDelimiters = literalDelimiters.sorted { $0.count > $1.count }
    }

    /// The prose documented by the comments written immediately above one declaration, in source
    /// order, each the verbatim comment text.
    ///
    /// `nil` unless the comment nearest the declaration is documentation: a plain comment sitting
    /// between the two detaches whatever is above it. A documentation block stands alone, while
    /// consecutive documentation lines form one run.
    public func prose(fromLeading comments: [String]) -> String? {
        guard let nearest = comments.last else { return nil }
        if let block = blockLines(of: nearest) { return prose(of: block) }
        var lines: [String] = []
        for comment in comments.reversed() {
            guard let stripped = lineCommentLines(of: comment) else { break }
            lines = stripped + lines
        }
        return prose(of: dedented(lines))
    }

    /// The prose inside a string literal serving as a declaration's documentation — quotes, and any
    /// prefix in front of them, removed.
    public func prose(fromLiteral literal: String) -> String? {
        let quoted = literal.drop { $0.isLetter }
        guard let delimiter = literalDelimiters.first(where: {
            quoted.hasPrefix($0) && quoted.count >= 2 * $0.count
        }) else { return nil }
        var body = quoted.dropFirst(delimiter.count)
        if body.hasSuffix(delimiter) {
            body = body.dropLast(delimiter.count)
        }
        return prose(of: openingLineAndDedentedRest(of: String(body)))
    }

    // MARK: - Markers

    private func lineCommentLines(of comment: String) -> [String]? {
        var lines: [String] = []
        for line in comment.trimmingTrailingWhitespace().components(separatedBy: "\n") {
            let text = line.drop(while: \.isHorizontalWhitespace)
            guard let prefix = linePrefixes.first(where: text.hasPrefix) else { return nil }
            lines.append(String(text.dropFirst(prefix.count)).droppingLeadingSpace())
        }
        return lines
    }

    private func blockLines(of comment: String) -> [String]? {
        let text = comment.trimmingTrailingWhitespace()
        let closing = blockClosing ?? ""
        guard let opening = blockOpenings.first(where: {
            text.hasPrefix($0) && text.count >= $0.count + closing.count
        }) else { return nil }
        var body = text.dropFirst(opening.count)
        if !closing.isEmpty, body.hasSuffix(closing) {
            body = body.dropLast(closing.count)
        }
        let lines = body.components(separatedBy: "\n").map { line in
            guard let marker = continuationMarker else { return line }
            let indented = line.drop(while: \.isHorizontalWhitespace)
            guard indented.hasPrefix(marker) else { return line }
            return String(indented.dropFirst(marker.count)).droppingLeadingSpace()
        }
        return openingLineAndDedentedRest(of: lines.joined(separator: "\n"))
    }

    // MARK: - Prose

    /// The opening delimiter indents the line it shares, so that line's own indentation is dropped
    /// and the shared indentation is measured from the lines below it.
    private func openingLineAndDedentedRest(of text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        let first = lines.isEmpty ? "" : String(lines.removeFirst().drop(while: \.isHorizontalWhitespace))
        return [first] + dedented(lines)
    }

    /// Blank edges removed. `nil` when nothing is left.
    private func prose(of lines: [String]) -> String? {
        var trimmed = lines.map { $0.trimmingTrailingWhitespace() }
        while trimmed.first?.isEmpty == true { trimmed.removeFirst() }
        while trimmed.last?.isEmpty == true { trimmed.removeLast() }
        return trimmed.isEmpty ? nil : trimmed.joined(separator: "\n")
    }

    /// `lines` with the indentation all of them share removed; a blank line counts for nothing.
    private func dedented(_ lines: [String]) -> [String] {
        let lines = lines.map { $0.trimmingTrailingWhitespace() }
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
