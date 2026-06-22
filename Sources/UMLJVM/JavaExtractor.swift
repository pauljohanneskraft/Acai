import UMLCore
import UMLTreeSitter

struct JavaExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    /// Names of every `enum_constant` in the file, so an unscoped enum constant assigned to a
    /// variable (`state = READY;`) is recognised as an enumerable value for state-machine analysis
    /// (mirrors the C/C++ extractor's handling).
    var declaredEnumConstants: Set<String> = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: [
                "class_declaration", "interface_declaration", "enum_declaration",
                "record_declaration", "annotation_type_declaration"
            ],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        declaredEnumConstants = collectEnumConstantNames(from: root)
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .java)
    }

    /// Walks the tree collecting the name of every `enum_constant`.
    private func collectEnumConstantNames(from root: Node) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node) {
            if node.nodeType == "enum_constant", let name = node.child(byFieldName: "name").map({ text($0) }) {
                names.insert(name)
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return names
    }
}
