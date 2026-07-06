import Foundation
import UMLCore
import UMLTreeSitter

struct DartExtractor: TreeSitterExtracting {

    /// Dart structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_element", "while_statement", "do_statement",
        "switch_statement_case", "switch_expression_case", "catch_clause"
    ]

    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: [
                "class_definition", "enum_declaration", "mixin_declaration",
                "extension_declaration", "extension_type_declaration"
            ],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        return buildArtifact(language: .dart)
    }
}
