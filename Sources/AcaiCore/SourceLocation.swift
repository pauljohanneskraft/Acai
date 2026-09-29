public struct SourceLocation: Codable, Equatable, Hashable, Sendable {
    public var filePath: String
    public var line: Int
    public var column: Int
    /// The last line the declaration spans, so a physical lines-of-code metric has an extent to
    /// measure. `nil` when the producer does not supply one — an aggregate can then tell a one-line
    /// declaration from an unmeasured one.
    public var endLine: Int?

    public init(filePath: String, line: Int, column: Int, endLine: Int? = nil) {
        self.filePath = filePath
        self.line = line
        self.column = column
        self.endLine = endLine
    }

    /// Physical lines covered, first line through ``endLine`` inclusive. `nil` when the extent is
    /// unknown; never below `1`, so a malformed extent cannot report a negative span.
    public var lineSpan: Int? {
        guard line > 0, let endLine else { return nil }
        return Swift.max(endLine - line + 1, 1)
    }
}
