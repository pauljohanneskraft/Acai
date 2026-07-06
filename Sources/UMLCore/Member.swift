/// One declared member of a type: a property, method, initializer, deinitializer, or subscript
/// (see `kind`). Carries the signature the diagram layer renders (name/type/parameters/modifiers)
/// plus optional body-derived analysis (`callSites`, `assignments`, `referencedTypeNames`) used by
/// sequence/call-graph/state diagrams and the coupling metrics. Parsers populate as much as their
/// language and analysis depth allow; downstream treats absent body data as "not analysed", never as
/// "none present".
public struct Member: Codable, Equatable, Hashable, Sendable {
    /// The member's source name (without any type qualifier).
    public var name: String
    /// What kind of member this is — selects the diagram compartment (see `isProperty`/`isMethod`).
    public var kind: MemberKind
    /// The member's visibility. Always set: each language parser resolves the language's default
    /// when the source has no explicit modifier, so the engine never has to guess downstream.
    public var accessLevel: AccessLevel
    /// The access level of the setter, when narrower than the getter
    /// (e.g. `private(set)`). `nil` when the setter matches `accessLevel`.
    public var setAccessLevel: AccessLevel?
    /// Declaration modifiers (`static`, `final`, `override`, …) in source order.
    public var modifiers: [Modifier]
    /// The member's type: a property's value type, or a method/initializer's return type. `nil` when
    /// the source declares none — note structural edges are only inferred when this is non-nil.
    public var type: TypeReference?
    /// The formal parameters, for methods/initializers/subscripts; empty for properties.
    public var parameters: [Parameter]
    /// The member's own generic parameters (e.g. a generic method's `<T>`).
    public var genericParameters: [GenericParameter]
    /// Whether this is a computed property (no stored backing) rather than a stored one.
    public var isComputed: Bool
    /// Raw annotation/attribute markers on the declaration (e.g. `@Published`, `@Override`).
    public var annotations: [String]
    /// Where the member is declared. Drives provenance-aware module attribution for edges this
    /// member produces (so a cross-module extension's members are attributed to the extension's file).
    public var location: SourceLocation?
    /// Statically-observable calls made inside this member's body.
    ///
    /// Populated by parsers when the call target can be determined from source.
    /// Empty for members whose bodies are not analysed (e.g. protocol requirements,
    /// abstract declarations) or when the parser does not yet emit call-site data.
    public var callSites: [CallSite]
    /// Statically-observable writes inside this member's body, in source order
    /// (the array position is the order of appearance; there is no index field).
    ///
    /// Populated by parsers for assignments whose target is a plain identifier or
    /// an explicit `self`/`this` member access. Empty for members whose bodies are
    /// not analysed or when the parser does not yet emit assignment data.
    public var assignments: [VariableAssignment]
    /// Statically-observable reads of stored properties inside this member's body.
    ///
    /// Populated by parsers for reads whose target is a bare identifier or an explicit
    /// `self`/`this` member access matching a known stored property (`receiver == nil`), plus
    /// `Type.field` static reads (`receiver` = the type name). Best-effort and language-dependent;
    /// consumed by the cohesion/feature-envy metrics (``LcomAnalysis``, ``FeatureEnvy``). Empty for
    /// members whose bodies are not analysed.
    public var fieldReads: [FieldAccess] = []
    /// For stored properties: the declaration initializer's classified value,
    /// when an initializer is present and the parser captures it.
    public var initialValue: VariableAssignment.Value?
    /// Bare type names referenced inside this member's body or initializer — constructions
    /// (`Foo()`), static/enum access (`Foo.bar`), casts/metatypes. Best-effort and language-dependent;
    /// consumed by the coupling metrics (``CodeArtifact/computeMetrics()``) to count construction/body
    /// dependencies that aren't visible in signatures. Not added to the relationship graph, so diagrams
    /// are unaffected.
    public var referencedTypeNames: [String] = []

    public init(
        name: String,
        kind: MemberKind,
        accessLevel: AccessLevel,
        setAccessLevel: AccessLevel? = nil,
        modifiers: [Modifier] = [],
        type: TypeReference? = nil,
        parameters: [Parameter] = [],
        genericParameters: [GenericParameter] = [],
        isComputed: Bool = false,
        annotations: [String] = [],
        location: SourceLocation? = nil,
        callSites: [CallSite] = [],
        assignments: [VariableAssignment] = [],
        fieldReads: [FieldAccess] = [],
        initialValue: VariableAssignment.Value? = nil,
        referencedTypeNames: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.setAccessLevel = setAccessLevel
        self.modifiers = modifiers
        self.type = type
        self.parameters = parameters
        self.genericParameters = genericParameters
        self.isComputed = isComputed
        self.annotations = annotations
        self.location = location
        self.callSites = callSites
        self.assignments = assignments
        self.fieldReads = fieldReads
        self.initialValue = initialValue
        self.referencedTypeNames = referencedTypeNames
    }

    /// Whether this member belongs in the "attributes" compartment of a class diagram.
    public var isProperty: Bool { kind == .property || kind == .subscript }

    /// Whether this member belongs in the "operations" compartment of a class diagram.
    public var isMethod: Bool { kind == .method || kind == .initializer || kind == .deinitializer }

    /// A stored property (data): a property with a stored backing, not a computed getter. The cohesion
    /// and data-class metrics reason about *stored fields*, so a computed property never qualifies.
    public var isStoredProperty: Bool { kind == .property && !isComputed }

    /// Behaviour (code, not data): methods/inits/deinits, computed properties (their getter is code),
    /// and subscripts. The complement of ``isStoredProperty`` — the two partition all members.
    public var isBehaviour: Bool { isMethod || (kind == .property && isComputed) || kind == .subscript }

    /// Whether this member is at least as visible as `minimum`. A `nil` `minimum` keeps everything.
    public func isVisible(atLeast minimum: AccessLevel?) -> Bool {
        guard let minimum else { return true }
        return accessLevel.visibilityRank >= minimum.visibilityRank
    }

    /// Whether this is a publicly *settable* stored property: its setter (`setAccessLevel`, or
    /// `accessLevel` when the setter isn't narrowed) is public/open. Mirrors the `mutablePublicState`
    /// smell — publicly mutable state that breaks encapsulation.
    public var isPubliclySettable: Bool {
        kind == .property && !isComputed
            && (setAccessLevel ?? accessLevel).visibilityRank >= AccessLevel.public.visibilityRank
    }
}

extension Sequence where Element == Member {
    /// The members at least as visible as `minimum` (see ``Member/isVisible(atLeast:)``).
    public func visible(atLeast minimum: AccessLevel?) -> [Member] {
        filter { $0.isVisible(atLeast: minimum) }
    }
}
