import AcaiCore
import AcaiLibrary
import AcaiTreeSitter
import TreeSitterJava

/// The Tree-sitter plugins the corpus covers, each paired with its inventory. Swift is absent: its
/// parser is SwiftSyntax, so it has no Tree-sitter node kinds.
struct NodeKindPlugins {

    var all: [NodeKindCorpus.Plugin] {
        [java]
    }

    private var java: NodeKindCorpus.Plugin {
        .init(
            stem: "java",
            grammars: ["java": grammar(tree_sitter_java(), as: .java)],
            parser: JavaCodeParser(),
            inventory: JavaNodeKinds().inventory
        )
    }








    private func grammar(
        _ language: OpaquePointer!, as sourceLanguage: CodeArtifact.SourceLanguage
    ) -> TreeSitterGrammar {
        TreeSitterGrammar(language: Language(language: language), sourceLanguage: sourceLanguage)
    }
}
