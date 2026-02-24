public struct SourceLocation: Codable, Equatable, Hashable, Sendable {
    public var filePath: String
    public var line: Int
    public var column: Int

    public init(filePath: String, line: Int, column: Int) {
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}
