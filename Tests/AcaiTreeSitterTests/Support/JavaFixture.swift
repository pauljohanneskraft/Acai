import AcaiCore
import TreeSitterJava
@testable import AcaiTreeSitter

struct JavaFixture {

    let context: SourceFileContext
    let root: Node

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
        root.walkPreorder { node in
            if node.nodeType == type { found.append(node) }
        }
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
