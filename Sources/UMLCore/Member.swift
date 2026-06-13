public struct Member: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var kind: MemberKind
    public var accessLevel: AccessLevel?
    /// The access level of the setter, when narrower than the getter
    /// (e.g. `private(set)`). `nil` when the setter matches `accessLevel`.
    public var setAccessLevel: AccessLevel?
    public var modifiers: [Modifier]
    public var type: TypeReference?
    public var parameters: [Parameter]
    public var genericParameters: [GenericParameter]
    public var isComputed: Bool
    public var annotations: [String]
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
    /// For stored properties: the declaration initializer's classified value,
    /// when an initializer is present and the parser captures it.
    public var initialValue: VariableAssignment.Value?

    public init(
        name: String,
        kind: MemberKind,
        accessLevel: AccessLevel? = nil,
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
        initialValue: VariableAssignment.Value? = nil
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
        self.initialValue = initialValue
    }
}
