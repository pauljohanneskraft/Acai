import AcaiCore
import AcaiTreeSitter

/// Reads a declaration's docstring.
///
/// Python's documentation is not a comment: it is the first statement of the declaration's own body,
/// written as a string literal. A `#` comment above a declaration documents nothing.
struct PythonDocstring {
    private let convention = DocumentationComment(
        literalDelimiters: ["\"\"\"", "'''", "\"", "'"]
    )

    let context: SourceFileContext

    func documentation(of node: Node) -> String? {
        guard let body = node.child(byFieldName: "body"),
              let statement = body.namedChildren().first,
              statement.nodeType == "expression_statement",
              let literal = statement.namedChildren().first,
              literal.nodeType == "string"
        else { return nil }
        return convention.prose(fromLiteral: literal.text(in: context))
    }
}
