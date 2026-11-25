import AcaiCore
import AcaiLibrary
import AcaiTreeSitter
import TreeSitterC
import TreeSitterCPP
import TreeSitterDart
import TreeSitterJava
import TreeSitterKotlin
import TreeSitterPython
import TreeSitterTSX
import TreeSitterTypeScript

/// The Tree-sitter plugins the corpus covers, each paired with its inventory. Swift is absent: its
/// parser is SwiftSyntax, so it has no Tree-sitter node kinds.
struct NodeKindPlugins {

    var all: [NodeKindCorpus.Plugin] {
        [java, kotlin, typeScript, javaScript, dart, python, c, cpp]
    }

    private var java: NodeKindCorpus.Plugin {
        .init(
            stem: "java",
            grammars: ["java": grammar(tree_sitter_java(), as: .java)],
            parser: JavaCodeParser(),
            inventory: JavaNodeKinds().inventory
        )
    }

    private var kotlin: NodeKindCorpus.Plugin {
        .init(
            stem: "kotlin",
            grammars: ["kt": grammar(tree_sitter_kotlin(), as: .kotlin)],
            parser: KotlinCodeParser(),
            inventory: KotlinNodeKinds().inventory
        )
    }

    /// `.ts` parses under the TypeScript grammar and `.tsx` under TSX, exactly as `JSCodeParser`
    /// routes them — only the extension says whether `<T>x` is a cast or JSX.
    private var typeScript: NodeKindCorpus.Plugin {
        .init(
            stem: "typescript",
            grammars: [
                "ts": grammar(tree_sitter_typescript(), as: .typeScript),
                "tsx": grammar(tree_sitter_tsx(), as: .typeScript)
            ],
            parser: JSCodeParser(isTypeScript: true),
            inventory: TypeScriptNodeKinds().inventory
        )
    }

    private var javaScript: NodeKindCorpus.Plugin {
        .init(
            stem: "javascript",
            grammars: [
                "js": grammar(tree_sitter_tsx(), as: .javaScript),
                "jsx": grammar(tree_sitter_tsx(), as: .javaScript)
            ],
            parser: JSCodeParser(isTypeScript: false),
            inventory: JavaScriptNodeKinds().inventory
        )
    }

    private var dart: NodeKindCorpus.Plugin {
        .init(
            stem: "dart",
            grammars: ["dart": grammar(tree_sitter_dart(), as: .dart)],
            parser: DartCodeParser(),
            inventory: DartNodeKinds().inventory
        )
    }

    private var python: NodeKindCorpus.Plugin {
        .init(
            stem: "python",
            grammars: ["py": grammar(tree_sitter_python(), as: .python)],
            parser: PythonCodeParser(),
            inventory: PythonNodeKinds().inventory
        )
    }

    private var c: NodeKindCorpus.Plugin {
        .init(
            stem: "c",
            grammars: ["c": grammar(tree_sitter_c(), as: .c), "h": grammar(tree_sitter_c(), as: .c)],
            parser: CCodeParser(),
            inventory: CNodeKinds().inventory
        )
    }

    private var cpp: NodeKindCorpus.Plugin {
        .init(
            stem: "cpp",
            grammars: ["cpp": grammar(tree_sitter_cpp(), as: .cpp), "hpp": grammar(tree_sitter_cpp(), as: .cpp)],
            parser: CppCodeParser(),
            inventory: CppNodeKinds().inventory
        )
    }

    private func grammar(
        _ language: OpaquePointer!, as sourceLanguage: CodeArtifact.SourceLanguage
    ) -> TreeSitterGrammar {
        TreeSitterGrammar(language: Language(language: language), sourceLanguage: sourceLanguage)
    }
}
