/// A single declared type (class, struct, enum, protocol/interface, …) and everything the diagram
/// and metrics layers need about it. Produced by a language parser, then resolved/merged during
/// ``CodeArtifact`` enrichment.
///
/// **Producer contract for identity** (the three name fields are *not* interchangeable):
/// - ``id`` and ``qualifiedName`` are the **namespace-qualified** identity and must be equal; this is
///   what relationship endpoints, ``extensionOf``, and nested-type prefixes resolve against.
/// - ``name`` is the **simple** name; it must match the simple names parsers emit in `TypeReference`
///   and `CallSite`. A naive plugin that swaps these silently renders broken/empty diagrams.
public struct TypeDeclaration: Codable, Equatable, Hashable, Sendable {
    /// Stable, namespace-qualified identity (equal to ``qualifiedName``). Relationship endpoints,
    /// ``extensionOf``, and nested-type ids resolve against this; a nested type's id must be
    /// hierarchically prefixed by its parent's id.
    public var id: String
    /// The **simple** (unqualified) source name — must match the simple names used in
    /// `TypeReference.name` and `CallSite.receiverType` for resolution to succeed.
    public var name: String
    /// The namespace/package-qualified name; equal to ``id``.
    public var qualifiedName: String
    /// The kind of type — selects the class-box stereotype and some edge semantics.
    public var kind: TypeKind
    /// The declaration's visibility. Always set: each language parser resolves the language's
    /// default when the source has no explicit modifier (Swift `internal`, Java `package-private`,
    /// Kotlin/Dart/Python/C-family `public`, …), so the engine never has to guess downstream.
    public var accessLevel: AccessLevel
    /// Declaration modifiers (`final`, `abstract`, `static`, …) in source order.
    public var modifiers: [Modifier]
    /// The type's own generic parameters (`<T>`).
    public var genericParameters: [GenericParameter]
    /// Protocol `associatedtype` requirements (distinct from generic parameters).
    public var associatedTypes: [GenericParameter]
    /// Supertypes and conformances as written at the declaration. Each is resolved to a target
    /// `id` during enrichment where one exists; unresolved entries render as external nodes.
    public var inheritedTypes: [TypeReference]
    /// The declared members (properties, methods, …); extension members are merged in here.
    public var members: [Member]
    /// The cases of an enum (empty for non-enums).
    public var enumCases: [EnumCase]
    /// Types declared inside this one; each nested id must be prefixed by ``id``.
    public var nestedTypes: [TypeDeclaration]
    /// Raw annotation/attribute markers on the declaration (e.g. `@objc`, `@Entity`).
    public var annotations: [String]
    /// When this declaration is an extension/category, the identity of the type it augments. Must
    /// match a target's ``qualifiedName``/``id``/``name`` *after generics are stripped* (`Foo<T>` →
    /// `Foo`), or the extension — and its conformances — are silently dropped during merging.
    public var extensionOf: String?
    /// The enclosing namespace/package, when the language has one. Feeds ``qualifiedName``.
    public var namespace: String?
    /// Where the type is declared (drives provenance-aware module attribution).
    public var location: SourceLocation?

    public init(
        id: String,
        name: String,
        qualifiedName: String,
        kind: TypeKind,
        accessLevel: AccessLevel,
        modifiers: [Modifier] = [],
        genericParameters: [GenericParameter] = [],
        associatedTypes: [GenericParameter] = [],
        inheritedTypes: [TypeReference] = [],
        members: [Member] = [],
        enumCases: [EnumCase] = [],
        nestedTypes: [TypeDeclaration] = [],
        annotations: [String] = [],
        extensionOf: String? = nil,
        namespace: String? = nil,
        location: SourceLocation? = nil
    ) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.genericParameters = genericParameters
        self.associatedTypes = associatedTypes
        self.inheritedTypes = inheritedTypes
        self.members = members
        self.enumCases = enumCases
        self.nestedTypes = nestedTypes
        self.annotations = annotations
        self.extensionOf = extensionOf
        self.namespace = namespace
        self.location = location
    }
}
