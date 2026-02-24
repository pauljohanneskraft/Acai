@_exported import SwiftTreeSitter

/// Navigation extensions on the tree-sitter `Node` type.
/// These are re-exported to any module that imports `UMLTreeSitter`,
/// so language-parser targets only need `import UMLTreeSitter`.
public extension Node {

    /// All children (named and anonymous).
    func children() -> [Node] {
        (0..<childCount).compactMap { child(at: $0) }
    }

    /// Only named (non-anonymous) children.
    func namedChildren() -> [Node] {
        children().filter(\.isNamed)
    }

    /// First named child.
    func firstNamedChild() -> Node? {
        (0..<childCount).lazy.compactMap { child(at: $0) }.first(where: \.isNamed)
    }

    /// First child whose `nodeType` equals `type`.
    func firstChild(withType type: String) -> Node? {
        (0..<childCount).lazy.compactMap { child(at: $0) }.first { $0.nodeType == type }
    }

    /// All children whose `nodeType` equals `type`.
    func allChildren(withType type: String) -> [Node] {
        children().filter { $0.nodeType == type }
    }

    /// Whether any direct child has the given `nodeType`.
    func hasChild(withType type: String) -> Bool {
        (0..<childCount).contains { child(at: $0)?.nodeType == type }
    }
}
