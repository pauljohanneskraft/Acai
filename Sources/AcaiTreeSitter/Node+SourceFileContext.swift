import Foundation
import AcaiCore

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

    public func location(in context: SourceFileContext) -> SourceLocation {
        let point = pointRange.lowerBound
        return SourceLocation(
            filePath: context.fileName,
            line: Int(point.row) + 1,
            column: Int(point.column) + 1
        )
    }

    // MARK: - Text-dependent child queries

    /// Useful for detecting grammar keywords such as `val`, `var`, `interface` that tree-sitter
    /// represents as anonymous (non-named) nodes.
    public func hasAnonymousChild(_ keyword: String, in context: SourceFileContext) -> Bool {
        children().contains { !$0.isNamed && $0.text(in: context) == keyword }
    }

    public func hasDirectChildText(_ text: String, in context: SourceFileContext) -> Bool {
        children().contains { $0.text(in: context) == text }
    }
}
