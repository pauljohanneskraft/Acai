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

    /// `1 +` the count of decision-point nodes (in `branchKinds`, supplied by the caller so this names
    /// no language) found while walking this node's subtree. A branch node whose type is a key in
    /// `fallbackMarkers` is skipped when one of its direct children has a type in that key's value —
    /// the fallback arm of a `switch`/`when`-style construct (`default`/`else`) is not itself a
    /// decision. Iterative (explicit stack) so a deeply nested body can't overflow the stack.
    func cyclomaticComplexity(branchKinds: Set<String>, fallbackMarkers: [String: Set<String>] = [:]) -> Int {
        var complexity = 1
        var stack: [Node] = [self]
        while let node = stack.popLast() {
            if let type = node.nodeType, branchKinds.contains(type),
               !node.isFallbackBranch(markers: fallbackMarkers[type]) {
                complexity += 1
            }
            for index in 0..<node.childCount {
                node.child(at: index).map { stack.append($0) }
            }
        }
        return complexity
    }

    private func isFallbackBranch(markers: Set<String>?) -> Bool {
        guard let markers else { return false }
        return children().contains { $0.nodeType.map(markers.contains) ?? false }
    }
}
