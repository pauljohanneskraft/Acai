public struct Member: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var kind: MemberKind
    public var accessLevel: AccessLevel?
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

    public init(
        name: String,
        kind: MemberKind,
        accessLevel: AccessLevel? = nil,
        modifiers: [Modifier] = [],
        type: TypeReference? = nil,
        parameters: [Parameter] = [],
        genericParameters: [GenericParameter] = [],
        isComputed: Bool = false,
        annotations: [String] = [],
        location: SourceLocation? = nil,
        callSites: [CallSite] = []
    ) {
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.type = type
        self.parameters = parameters
        self.genericParameters = genericParameters
        self.isComputed = isComputed
        self.annotations = annotations
        self.location = location
        self.callSites = callSites
    }
}
