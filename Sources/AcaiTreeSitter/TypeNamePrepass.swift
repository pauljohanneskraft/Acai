import SwiftTreeSitter

/// Collects the simple names of every type declared in a file, before any body is extracted, so
/// call-site resolution sees types declared after the body that refers to them.
///
/// The reader is a per-call parameter rather than a stored property so it stays non-escaping:
/// extractors call this from a `mutating` method, and a stored closure would capture `inout self`.
public struct TypeNamePrepass {

    private let declarationNodeTypes: Set<String>

    public init(declarationNodeTypes: Set<String>) {
        self.declarationNodeTypes = declarationNodeTypes
    }

    /// Declarations whose name can't be read are skipped.
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
