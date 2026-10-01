import AcaiCore

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

private let jvmExcludedDirectories: Set<String> = ["build", "target", "bin", "out", ".gradle", ".idea"]

/// JVM entry points invoked by frameworks rather than resolvable call sites: JUnit test methods and
/// lifecycle callbacks, Spring bean lifecycle hooks, and `@Override` methods (handled agnostically);
/// `main` is the process entry point.
private let jvmEntryPointMarkers = EntryPointMarkers(
    annotations: [
        "test", "beforeeach", "aftereach", "beforeall", "afterall", "before", "after",
        "parameterizedtest", "postconstruct", "predestroy", "eventlistener", "scheduled", "bean"
    ],
    methodNames: ["main"])

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
            excludedDirectories: jvmExcludedDirectories,
            entryPointMarkers: jvmEntryPointMarkers,
            // `JavaCallSiteSyntax` now also matches `object_creation_expression`: `new Thing()`
            // resolves to a call-site edge targeting the constructor, named after the type itself.
            deadCodeMemberKinds: [.method, .initializer]
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
            excludedDirectories: jvmExcludedDirectories,
            entryPointMarkers: jvmEntryPointMarkers,
            // `Thing(1)` now resolves through `CallSiteScope.bareCall`'s constructor opt-in to a
            // call-site edge targeting the constructor's fixed `init` member. An `operator fun get`
            // is extracted as a method and is scanned as one.
            deadCodeMemberKinds: [.method, .initializer],
            varianceKeywords: [.covariant: "out", .contravariant: "in"]
        )
    }
}
