import Foundation
import UMLCore

// MARK: - Node text and location (require a SourceFileContext)

extension Node {

    /// The source text covered by this node.
    ///
    /// Uses `node.range` (an `NSRange` in UTF-16 code units) with `NSString` bridging,
    /// which matches how swift-tree-sitter stores the source internally.
    public func text(in context: SourceFileContext) -> String {
        let nsStr = context.source as NSString
        let nsRange = range
        guard nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= nsStr.length else { return "" }
        return nsStr.substring(with: nsRange)
    }

    /// The source location of this node's start position.
    public func location(in context: SourceFileContext) -> SourceLocation {
        let point = pointRange.lowerBound
        return SourceLocation(
            filePath: context.fileName,
            line: Int(point.row) + 1,
            column: Int(point.column) + 1
        )
    }

    // MARK: - Text-dependent child queries

    /// Returns `true` if any **anonymous** (non-named) direct child's text equals `keyword`.
    ///
    /// Useful for detecting grammar keywords such as `val`, `var`, `interface` that
    /// tree-sitter represents as anonymous nodes.
    public func hasAnonymousChild(_ keyword: String, in context: SourceFileContext) -> Bool {
        children().contains { !$0.isNamed && $0.text(in: context) == keyword }
    }

    /// Returns `true` if any direct child's text (named or anonymous) equals `text`.
    public func hasDirectChildText(_ text: String, in context: SourceFileContext) -> Bool {
        children().contains { $0.text(in: context) == text }
    }
}
