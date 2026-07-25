import SwiftTreeSitter

/// A table-driven dispatcher over a node's direct children: maps each child's grammar `nodeType` to a
/// caller-defined `Action` and vends the children that matched, in source order. Factors out the
/// "walk children, look up nodeType in a table, act on hits" loop several extractors repeat — the
/// extractor keeps its own `Action` enum, table, and mutation; only the walk lives here.
public struct NodeDispatch<Action> {
    /// Grammar `nodeType` → the action to take for a child of that type. Types absent from the table
    /// are skipped.
    public let table: [String: Action]

    public init(_ table: [String: Action]) {
        self.table = table
    }

    /// The action mapped to `node`'s grammar type, or `nil` when the type isn't in the table.
    public func action(for node: Node) -> Action? {
        node.nodeType.flatMap { table[$0] }
    }

    /// Every direct child that maps to an action, paired with that action, in source order. Iterates
    /// `children()` (not just named children) so it can replace the extractors' existing raw walks
    /// byte-for-byte.
    public func matches(in node: Node) -> [(node: Node, action: Action)] {
        node.children().compactMap { child in action(for: child).map { (child, $0) } }
    }
}
