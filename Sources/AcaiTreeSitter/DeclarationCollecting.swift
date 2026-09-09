import AcaiCore

// MARK: - DeclarationCollecting

/// A `TreeSitterExtracting` conformer that keeps its declaration/relationship bookkeeping in one
/// `DeclarationCollector` value instead of six loose properties. Conforming needs only the stored
/// `declarations` property below — this extension supplies `TreeSitterExtracting`'s six required
/// state properties as computed forwards, so no per-language extractor writes that forwarding by
/// hand. This is the reusable half of moving `DeclarationCollector` to `AcaiCore`: any Tree-sitter
/// extractor can adopt it and get the six properties for free, instead of duplicating the same
/// get/set boilerplate per language.
public protocol DeclarationCollecting: TreeSitterExtracting {
    var declarations: DeclarationCollector { get set }
}

extension DeclarationCollecting {
    public var types: [TypeDeclaration] {
        get { declarations.types }
        set { declarations.types = newValue }
    }
    public var relationships: [Relationship] {
        get { declarations.relationships }
        set { declarations.relationships = newValue }
    }
    public var freestandingFunctions: [Member] {
        get { declarations.freestandingFunctions }
        set { declarations.freestandingFunctions = newValue }
    }
    public var globalVariables: [Member] {
        get { declarations.globalVariables }
        set { declarations.globalVariables = newValue }
    }
    public var currentNamespace: String? {
        get { declarations.currentNamespace }
        set { declarations.currentNamespace = newValue }
    }
    public var declaredTypeNames: Set<String> {
        get { declarations.declaredTypeNames }
        set { declarations.declaredTypeNames = newValue }
    }
}
