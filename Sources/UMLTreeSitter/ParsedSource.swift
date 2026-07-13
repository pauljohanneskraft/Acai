import Foundation
@preconcurrency import SwiftTreeSitter
import UMLCore

/// One parsed source file: its tree, root node, and the raw text needed to read node text/locations
/// and to build a `Predicate.Context` for query-predicate evaluation.
public struct ParsedSource: Sendable {
    public let tree: Tree
    public let rootNode: Node
    public let text: String
    public let fileName: String

    /// `mutableTree` is copied to an immutable, `Sendable` `Tree` (what `SwiftTreeSitter.Parser`
    /// actually produces is a `MutableTree`, which itself is not `Sendable`).
    public init?(mutableTree: MutableTree, text: String, fileName: String) {
        guard let tree = mutableTree.copy(), let rootNode = tree.rootNode else { return nil }
        self.tree = tree
        self.rootNode = rootNode
        self.text = text
        self.fileName = fileName
    }
}

extension Node {

    /// The source text covered by this node, read against `source`'s raw text.
    public func text(in source: ParsedSource) -> String {
        let nsText = source.text as NSString
        let nsRange = range
        guard nsRange.location != NSNotFound, nsRange.location + nsRange.length <= nsText.length else { return "" }
        return nsText.substring(with: nsRange)
    }

    /// This node's start position, as a `SourceLocation` against `source`'s file name.
    public func location(in source: ParsedSource) -> SourceLocation {
        let point = pointRange.lowerBound
        return SourceLocation(filePath: source.fileName, line: Int(point.row) + 1, column: Int(point.column) + 1)
    }
}

extension Node {

    /// All children (named and anonymous).
    public func children() -> [Node] {
        (0..<childCount).compactMap { child(at: $0) }
    }

    /// Only named (non-anonymous) children.
    public func namedChildren() -> [Node] {
        children().filter(\.isNamed)
    }
}
