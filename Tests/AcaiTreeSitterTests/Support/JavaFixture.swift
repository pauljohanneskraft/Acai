import AcaiCore
import TreeSitterJava
@testable import AcaiTreeSitter

/// A parsed Java file plus the context the shared seams read text and locations through.
///
/// `Node` holds its `Tree`, so keeping the root alive keeps the tree alive.
struct JavaFixture {

    let context: SourceFileContext
    let root: Node

    /// `nil` only when the grammar fails to load or produces no tree — a packaging failure, not
    /// something a malformed snippet can cause.
    init?(_ source: String, fileName: String = "Fixture.java") {
        let grammar = TreeSitterGrammar(
            language: Language(language: tree_sitter_java()),
            sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "java"))
        guard let parser = grammar.makeParser(),
              let tree = parser.parse(source),
              let root = tree.rootNode
        else { return nil }
        self.context = SourceFileContext(source: source, fileName: fileName)
        self.root = root
    }

    /// Every node of `type` in the subtree, in pre-order, unnamed nodes included.
    func nodes(ofType type: String) -> [Node] {
        var found: [Node] = []
        func walk(_ node: Node) {
            if node.nodeType == type { found.append(node) }
            for child in node.children() { walk(child) }
        }
        walk(root)
        return found
    }

    func firstNode(ofType type: String) -> Node? {
        nodes(ofType: type).first
    }

    /// The `block` body of the method named `name`.
    func methodBody(_ name: String) -> Node? {
        nodes(ofType: "method_declaration")
            .first { $0.child(byFieldName: "name")?.text(in: context) == name }?
            .child(byFieldName: "body")
    }
}
