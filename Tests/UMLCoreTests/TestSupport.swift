import UMLCore

// UMLCoreTests exercises the agnostic enrichment engine directly, without a parser or language
// module. This fixture supplies a representative classification (the union of the built-in
// languages, matching the engine's former global behaviour) so the generic `enriched()` tests keep
// their expectations. Production never has an empty or implicit configuration; tests opt into this
// one explicitly.
extension CodeArtifact.SourceLanguage {
    static let swift = CodeArtifact.SourceLanguage(rawValue: "swift")
    static let java = CodeArtifact.SourceLanguage(rawValue: "java")
    static let kotlin = CodeArtifact.SourceLanguage(rawValue: "kotlin")
    static let typeScript = CodeArtifact.SourceLanguage(rawValue: "typeScript")
    static let javaScript = CodeArtifact.SourceLanguage(rawValue: "javaScript")
    static let dart = CodeArtifact.SourceLanguage(rawValue: "dart")
}

extension LanguageConfiguration {
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
        ]
    )
}

extension CodeArtifact {
    /// Test convenience mirroring the former no-argument `enriched()` using the `.test` fixture.
    func enriched() -> CodeArtifact { enriched(configuration: .test) }
}
