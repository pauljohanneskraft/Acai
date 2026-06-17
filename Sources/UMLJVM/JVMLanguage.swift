import UMLCore

// Java and Kotlin share one target because they share the JVM build systems (Gradle/Maven) and
// their `JVMBuildSystemDetector`. Each still has its own parser, identity, and configuration.

extension CodeArtifact.SourceLanguage {
    public static let java = CodeArtifact.SourceLanguage(rawValue: "java")
    public static let kotlin = CodeArtifact.SourceLanguage(rawValue: "kotlin")
}

/// Framework annotation → UML stereotype markers for the JVM ecosystem (JPA / Jakarta Persistence
/// and Spring). Shared by both JVM languages, since both use these frameworks.
private let jvmAnnotationStereotypes: [String: String] = [
    "entity": "entity",
    "table": "entity",
    "embeddable": "embeddable",
    "repository": "repository",
    "service": "service",
    "controller": "controller",
    "restcontroller": "controller",
    "component": "component"
]

/// Build-output / tooling directories common to Gradle and Maven projects.
private let jvmExcludedDirectories: Set<String> = ["build", "target", "bin", "out", ".gradle", ".idea"]

extension JavaCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "void", "Void",
                "int", "long", "short", "byte", "float", "double", "boolean", "char",
                "Integer", "Long", "Short", "Byte", "Boolean", "Float", "Double", "Character",
                "String", "Object", "Number", "Serializable", "Cloneable", "Optional"
            ],
            collectionTypeNames: [
                "List", "ArrayList", "LinkedList", "Vector", "Stack", "Queue", "Deque",
                "ArrayDeque", "PriorityQueue",
                "Set", "HashSet", "TreeSet", "LinkedHashSet",
                "Map", "HashMap", "TreeMap", "LinkedHashMap",
                "Collection", "Iterable"
            ],
            annotationStereotypes: jvmAnnotationStereotypes,
            excludedDirectories: jvmExcludedDirectories
        )
    }
}

extension KotlinCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "Unit", "Nothing", "Any",
                "String", "Int", "Double", "Float", "Boolean", "Char", "Long", "Short", "Byte",
                "Number", "Optional"
            ],
            collectionTypeNames: [
                "List", "MutableList", "ArrayList",
                "Set", "MutableSet", "HashSet", "LinkedHashSet",
                "Map", "MutableMap", "HashMap", "LinkedHashMap",
                "Collection", "Iterable", "Sequence", "Array", "ArrayDeque"
            ],
            annotationStereotypes: jvmAnnotationStereotypes,
            excludedDirectories: jvmExcludedDirectories
        )
    }
}
