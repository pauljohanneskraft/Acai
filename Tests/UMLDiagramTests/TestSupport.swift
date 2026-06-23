import UMLCore
@testable import UMLDiagram

// Diagram unit tests build synthetic artifacts and exercise the agnostic diagram layer directly,
// without the language registry that production resolves configuration from. This file restores
// the pre-refactor ergonomics for tests only: language constants for building artifacts, a
// representative `LanguageConfiguration` fixture (the union of the built-in languages' classification
// + framework stereotypes, matching the engine's former global behaviour), and convenience
// initializers that inject that fixture so existing call sites keep compiling. Production stays
// strict — it never has an empty or implicit language configuration.

extension CodeArtifact.SourceLanguage {
    static let swift = CodeArtifact.SourceLanguage(rawValue: "swift")
    static let java = CodeArtifact.SourceLanguage(rawValue: "java")
    static let kotlin = CodeArtifact.SourceLanguage(rawValue: "kotlin")
    static let typeScript = CodeArtifact.SourceLanguage(rawValue: "typeScript")
    static let javaScript = CodeArtifact.SourceLanguage(rawValue: "javaScript")
    static let dart = CodeArtifact.SourceLanguage(rawValue: "dart")
}

extension LanguageConfiguration {
    /// Representative classification + framework stereotypes for diagram unit tests, standing in for
    /// what production resolves from the registry. Deliberately a broad union so tests don't depend
    /// on any single language's exact set.
    static let test = LanguageConfiguration(
        primitiveTypeNames: [
            "void", "Void", "Unit", "Nothing", "Never", "Any", "AnyObject", "any",
            "Self", "self", "this",
            "String", "Int", "Double", "Float", "Bool", "Character", "UInt",
            "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64",
            "CGFloat", "Data", "Date", "URL", "UUID", "Error", "Sendable", "Codable",
            "Equatable", "Hashable", "Comparable", "Identifiable", "CustomStringConvertible",
            "int", "long", "short", "byte", "float", "double", "boolean", "char",
            "Integer", "Long", "Short", "Byte", "Boolean",
            "Object", "Number", "Serializable", "Cloneable",
            "string", "number", "undefined", "null", "symbol", "bigint",
            "unknown", "never", "object", "Promise", "Function",
            "dynamic", "num", "var", "inferred",
            "Optional"
        ],
        collectionTypeNames: [
            "List", "ArrayList", "LinkedList", "Vector", "Stack", "Queue", "Deque",
            "ArrayDeque", "PriorityQueue",
            "Set", "HashSet", "TreeSet", "LinkedHashSet", "MutableSet",
            "Map", "HashMap", "TreeMap", "LinkedHashMap", "MutableMap",
            "Array", "MutableList", "Iterable", "Collection", "Sequence",
            "Dictionary"
        ],
        annotationStereotypes: [
            "entity": "entity",
            "table": "entity",
            "embeddable": "embeddable",
            "repository": "repository",
            "service": "service",
            "controller": "controller",
            "restcontroller": "controller",
            "component": "component"
        ]
    )
}

extension ClassDiagramOptions {
    /// Test convenience mirroring the production initializer minus `language`, injecting `.test`.
    init(
        layoutDirection: LayoutDirection = .topToBottom,
        showMembers: Bool = true,
        showMemberTypes: Bool = true,
        showAccessLevelSymbols: Bool = true,
        minimumAccessLevel: AccessLevel? = nil,
        includedRelationshipKinds: Set<Relationship.Kind> = Set(Relationship.Kind.allCases),
        groupBy: GroupingStrategy = .none,
        showGenericParameters: Bool = true,
        fontName: String = "Helvetica",
        fontSize: Int = 12,
        theme: DiagramTheme? = nil,
        inferCompositionFromProperties: Bool = true,
        inferDependencyFromMethods: Bool = true,
        showExternalTypes: Bool = false,
        showMultiplicities: Bool = true,
        showAnnotationStereotypes: Bool = true,
        focus: FocusConfiguration? = nil
    ) {
        self.init(
            layoutDirection: layoutDirection,
            showMembers: showMembers,
            showMemberTypes: showMemberTypes,
            showAccessLevelSymbols: showAccessLevelSymbols,
            minimumAccessLevel: minimumAccessLevel,
            includedRelationshipKinds: includedRelationshipKinds,
            groupBy: groupBy,
            showGenericParameters: showGenericParameters,
            fontName: fontName,
            fontSize: fontSize,
            theme: theme,
            inferCompositionFromProperties: inferCompositionFromProperties,
            inferDependencyFromMethods: inferDependencyFromMethods,
            showExternalTypes: showExternalTypes,
            showMultiplicities: showMultiplicities,
            showAnnotationStereotypes: showAnnotationStereotypes,
            focus: focus,
            language: .test
        )
    }
}

extension DOTGenerator {
    /// Test convenience: a generator with default options bound to the `.test` language fixture.
    init() { self.init(options: ClassDiagramOptions()) }
}

extension ClassDiagramMermaidRenderer {
    /// Test convenience: a renderer with default options bound to the `.test` language fixture.
    init() { self.init(options: ClassDiagramOptions()) }
}

extension CodeArtifact {
    /// Test convenience mirroring the former no-argument `enriched()` using the `.test` fixture.
    func enriched() -> CodeArtifact { enriched(configuration: .test) }
}

extension ClassDiagram {
    /// Test convenience building a `ClassDiagram` with the `.test` language fixture.
    init(_ artifact: CodeArtifact) {
        self.init(artifact: artifact, options: EnrichmentOptions(language: .test))
    }
}
