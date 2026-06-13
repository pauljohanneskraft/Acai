// Backward-compatible decoding.
//
// Newly-added non-optional fields (`CodeArtifact.globalVariables`,
// `Metadata.hasParseErrors`, `TypeDeclaration.associatedTypes`) would otherwise make
// synthesized `Decodable` *require* those keys, breaking analyses stored before they
// existed (`uml list`, `diagram --from <name>`). These custom decoders default any
// missing key, so older stored JSON still loads. Encoding stays synthesized.

extension CodeArtifact {
    enum CodingKeys: String, CodingKey {
        case metadata, types, relationships, freestandingFunctions, globalVariables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(Metadata.self, forKey: .metadata)
        types = try container.decodeIfPresent([TypeDeclaration].self, forKey: .types) ?? []
        relationships = try container.decodeIfPresent([Relationship].self, forKey: .relationships) ?? []
        freestandingFunctions = try container.decodeIfPresent([Member].self, forKey: .freestandingFunctions) ?? []
        globalVariables = try container.decodeIfPresent([Member].self, forKey: .globalVariables) ?? []
    }
}

extension CodeArtifact.Metadata {
    enum CodingKeys: String, CodingKey {
        case sourceLanguage, filePaths, toolVersion, hasParseErrors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLanguage = try container.decode(CodeArtifact.SourceLanguage.self, forKey: .sourceLanguage)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        toolVersion = try container.decodeIfPresent(String.self, forKey: .toolVersion)
        hasParseErrors = try container.decodeIfPresent(Bool.self, forKey: .hasParseErrors) ?? false
    }
}

extension TypeDeclaration {
    enum CodingKeys: String, CodingKey {
        case id, name, qualifiedName, kind, accessLevel, modifiers, genericParameters
        case associatedTypes, inheritedTypes, members, enumCases, nestedTypes
        case annotations, extensionOf, namespace, location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        qualifiedName = try container.decode(String.self, forKey: .qualifiedName)
        kind = try container.decode(TypeKind.self, forKey: .kind)
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel)
        modifiers = try container.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
        genericParameters = try container.decodeIfPresent([GenericParameter].self, forKey: .genericParameters) ?? []
        associatedTypes = try container.decodeIfPresent([GenericParameter].self, forKey: .associatedTypes) ?? []
        inheritedTypes = try container.decodeIfPresent([TypeReference].self, forKey: .inheritedTypes) ?? []
        members = try container.decodeIfPresent([Member].self, forKey: .members) ?? []
        enumCases = try container.decodeIfPresent([EnumCase].self, forKey: .enumCases) ?? []
        nestedTypes = try container.decodeIfPresent([TypeDeclaration].self, forKey: .nestedTypes) ?? []
        annotations = try container.decodeIfPresent([String].self, forKey: .annotations) ?? []
        extensionOf = try container.decodeIfPresent(String.self, forKey: .extensionOf)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        location = try container.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

extension Member {
    enum CodingKeys: String, CodingKey {
        case name, kind, accessLevel, setAccessLevel, modifiers, type, parameters
        case genericParameters, isComputed, annotations, location, callSites
        case assignments, initialValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(MemberKind.self, forKey: .kind)
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel)
        setAccessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .setAccessLevel)
        modifiers = try container.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
        type = try container.decodeIfPresent(TypeReference.self, forKey: .type)
        parameters = try container.decodeIfPresent([Parameter].self, forKey: .parameters) ?? []
        genericParameters = try container.decodeIfPresent([GenericParameter].self, forKey: .genericParameters) ?? []
        isComputed = try container.decodeIfPresent(Bool.self, forKey: .isComputed) ?? false
        annotations = try container.decodeIfPresent([String].self, forKey: .annotations) ?? []
        location = try container.decodeIfPresent(SourceLocation.self, forKey: .location)
        callSites = try container.decodeIfPresent([CallSite].self, forKey: .callSites) ?? []
        assignments = try container.decodeIfPresent([VariableAssignment].self, forKey: .assignments) ?? []
        initialValue = try container.decodeIfPresent(VariableAssignment.Value.self, forKey: .initialValue)
    }
}
