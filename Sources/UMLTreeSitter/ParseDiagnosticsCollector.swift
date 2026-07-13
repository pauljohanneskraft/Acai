@preconcurrency import SwiftTreeSitter
import UMLCore

/// Walks a parsed tree for concrete `ERROR`/`missing` nodes — grammar-agnostic Tree-sitter
/// primitives, so this is the same for every language. Reports the specific offending nodes rather
/// than trusting a root node's aggregate `hasError`, which is known to false-positive on at least
/// one grammar in this project (tree-sitter-kotlin, terse single-line class bodies).
public struct ParseDiagnosticsCollector: Sendable {
    public init() {}

    public func diagnostics(in source: ParsedSource) -> [ParseDiagnostic] {
        var diagnostics: [ParseDiagnostic] = []
        walk(source.rootNode, source: source, into: &diagnostics)
        return diagnostics
    }

    private func walk(_ node: Node, source: ParsedSource, into diagnostics: inout [ParseDiagnostic]) {
        if node.isMissing {
            diagnostics.append(ParseDiagnostic(
                location: node.location(in: source), kind: .missing,
                message: "missing \(node.nodeType ?? "token")"))
        } else if node.nodeType == "ERROR" {
            diagnostics.append(ParseDiagnostic(
                location: node.location(in: source), kind: .error, message: "unexpected syntax"))
        }
        for child in node.children() {
            walk(child, source: source, into: &diagnostics)
        }
    }
}
