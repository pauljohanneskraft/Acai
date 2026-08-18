public struct SourceFileContext: Sendable {
    public let source: String
    public let fileName: String

    public init(source: String, fileName: String) {
        self.source = source
        self.fileName = fileName
    }
}
