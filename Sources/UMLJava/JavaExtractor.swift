import UMLCore
import UMLTreeSitter

struct JavaExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .java)
    }
}
