/// The source-file context needed to interpret tree-sitter `Node` positions and text.
///
/// swift-tree-sitter encodes source strings as UTF-16 internally, so `node.byteRange`
/// gives UTF-16 byte offsets. The `node.range` property converts these to a correct
/// `NSRange` (UTF-16 code-unit positions). Text extraction therefore uses the
/// `NSString`/`NSRange` bridge — see `Node.text(in:)`.
public struct SourceFileContext: Sendable {
    public let source: String
    public let fileName: String

    public init(source: String, fileName: String) {
        self.source = source
        self.fileName = fileName
    }
}
