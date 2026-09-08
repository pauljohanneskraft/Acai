import AcaiCore
import AcaiTreeSitter

struct PythonExtractor: DeclarationCollecting, CallSiteResolving {
    let context: SourceFileContext

    /// The declaration/relationship bookkeeping this extractor accumulates while walking, factored
    /// into its own shared type (`DeclarationCollector`). `DeclarationCollecting` supplies
    /// `TreeSitterExtracting`'s six required state properties as forwards onto this, so this
    /// extractor doesn't restate that plumbing itself.
    var declarations = DeclarationCollector()
    var topLevelCallSites: [CallSite] = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class_definition"],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.buildArtifact(language: .python, fileName: context.fileName)
    }

    // MARK: - Access Level (naming convention)

    /// Python has no access keywords; visibility is conveyed by leading underscores (dunders are
    /// public, `__x` is name-mangled private, `_x` is protected).
    func accessLevel(forName name: String) -> AccessLevel {
        if name.hasPrefix("__") && name.hasSuffix("__") { return .public }
        if name.hasPrefix("__") { return .private }
        if name.hasPrefix("_") { return .protected }
        return .public
    }
}
