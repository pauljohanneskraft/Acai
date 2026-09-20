import AcaiCore

/// Collects concrete parse problems from a best-effort tree: `ERROR` nodes and `missing` nodes (a
/// required token the source omitted).
///
/// Walks all children, not just named ones, since error/missing nodes are frequently unnamed.
/// Grammar-agnostic — `Node.isMissing` and the `ERROR` node type are Tree-sitter primitives, so the
/// same instance works for every language.
public struct ParseDiagnosticsCollector {

    private let context: SourceFileContext

    public init(context: SourceFileContext) {
        self.context = context
    }

    /// Call only when `root.hasError`; on a clean tree this walks the whole file to find nothing.
    public func diagnostics(in root: Node) -> [ParseDiagnostic] {
        var diagnostics: [ParseDiagnostic] = []
        func walk(_ node: Node) {
            if node.isMissing {
                diagnostics.append(ParseDiagnostic(
                    location: node.location(in: context), kind: .missing,
                    message: "missing \(node.nodeType ?? "token")"
                ))
            } else if node.nodeType == "ERROR" {
                diagnostics.append(ParseDiagnostic(
                    location: node.location(in: context), kind: .error, message: "unexpected syntax"
                ))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return diagnostics
    }
}
