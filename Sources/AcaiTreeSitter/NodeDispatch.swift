import SwiftTreeSitter

/// Factors out the "walk children, look up nodeType in a table, act on hits" loop several extractors
/// repeat — the extractor keeps its own `Action` enum, table, and mutation; only the walk lives here.
public struct NodeDispatch<Action> {
    /// Types absent from the table are skipped.
    public let table: [String: Action]

    public init(_ table: [String: Action]) {
        self.table = table
    }

    public func action(for node: Node) -> Action? {
        node.nodeType.flatMap { table[$0] }
    }

    /// Iterates all children, not just named ones.
    public func matches(in node: Node) -> [(node: Node, action: Action)] {
        node.children().compactMap { child in action(for: child).map { (child, $0) } }
    }
}
