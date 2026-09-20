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

    /// Every identifier-like name in this subtree. Walks iteratively (explicit stack) so a deeply
    /// nested body can't overflow the stack. Over-captures every identifier by design; the engine
    /// keeps only names that resolve to a known type.
    ///
    /// Sorted, not in `Set` order: `CodeArtifact` is `Equatable`/`Hashable`/`Codable`, so an
    /// unordered result makes two parses of the same file compare unequal.
    public func referencedTypeNames(in context: SourceFileContext) -> [String] {
        var names: Set<String> = []
        var stack: [Node] = [self]
        while let node = stack.popLast() {
            if node.nodeType?.hasSuffix("identifier") == true {
                names.insert(node.text(in: context))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map { stack.append($0) }
            }
        }
        return names.sorted()
    }
}
