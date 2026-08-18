@_exported import SwiftTreeSitter

public extension Node {
    func children() -> [Node] {
        (0..<childCount).compactMap { child(at: $0) }
    }

    func namedChildren() -> [Node] {
        children().filter(\.isNamed)
    }

    func firstChild(withType type: String) -> Node? {
        (0..<childCount).lazy.compactMap { child(at: $0) }.first { $0.nodeType == type }
    }

    func allChildren(withType type: String) -> [Node] {
        children().filter { $0.nodeType == type }
    }

    func hasChild(withType type: String) -> Bool {
        (0..<childCount).contains { child(at: $0)?.nodeType == type }
    }
}
