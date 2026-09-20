import SwiftTreeSitter

/// Collects the simple names of every type declared in a file, in one pass before any body is
/// extracted, so call-site resolution sees the complete set — including a type declared *after*
/// the body that refers to it.
///
/// The traversal is shared; what a language supplies is which node types are declarations, and a
/// reader that pulls a name out of one. Declarations whose name can't be read are skipped.
///
/// The reader is a per-call parameter rather than a stored property so it stays non-escaping: an
/// extractor is a `struct` that calls this from a `mutating` method, and a stored closure would
/// have to capture its `inout self`.
public struct TypeNamePrepass {

    private let declarationNodeTypes: Set<String>

    public init(declarationNodeTypes: Set<String>) {
        self.declarationNodeTypes = declarationNodeTypes
    }

    public func names(in root: Node, name: (Node) -> String?) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node) {
            if let type = node.nodeType, declarationNodeTypes.contains(type), let typeName = name(node) {
                names.insert(typeName)
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return names
    }
}
