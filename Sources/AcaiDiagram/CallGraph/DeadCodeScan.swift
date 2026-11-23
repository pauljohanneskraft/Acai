import AcaiCore

/// Members that no resolved call edge targets and that aren't reachable by contract — dead-code
/// *candidates*. Because call resolution is best-effort, the report always carries the call graph's
/// `coverage`: the lower the coverage, the more of these are false positives (a real caller the parser
/// couldn't resolve), so a consumer reads them as leads, not verdicts.
///
/// Which member kinds are considered is the language's call to make, via
/// `LanguageConfiguration.deadCodeMemberKinds`: a kind whose call sites the parser never records can
/// have no caller edge, so scanning it would report every declaration of it as uncalled. Methods are
/// scanned in every language; initializers and subscripts only where their calls are recorded.
///
/// A value you instantiate over an artifact plus the language's `EntryPointMarkers`
/// (`DeadCodeScan(artifact:entryPoints:).report`). The universal reachability rules (public API,
/// `override`, protocol/interface requirements) are applied here; the language-specific test/framework
/// markers come from the injected configuration, so this names no language.
public struct DeadCodeScan: Sendable {
    public struct Candidate: Codable, Hashable, Sendable {
        /// The call-graph node id this member would have.
        public var id: String
        /// The owning type as the id names it; `nil` for a freestanding function.
        public var typeName: String?
        public var memberName: String
        public var location: SourceLocation?

        public init(id: String, typeName: String?, memberName: String, location: SourceLocation?) {
            self.id = id
            self.typeName = typeName
            self.memberName = memberName
            self.location = location
        }
    }

    public struct Report: Codable, Hashable, Sendable {
        /// The call graph's resolution coverage — the false-positive floor for `candidates`.
        public var coverage: CallGraph.Coverage
        /// The **union**, across every language in the artifact, of the kinds each one scanned, in
        /// `MemberKind` order. A kind appearing here was scanned for at least one language in the
        /// artifact, not necessarily every one — a polyglot codebase where one language scans
        /// subscripts and another doesn't still reports `subscripts` here. Reading it as "no
        /// candidate for this kind anywhere" is only safe when every language in the artifact agrees
        /// on `deadCodeMemberKinds`.
        public var scannedKinds: [MemberKind]
        public var candidates: [Candidate]
    }

    private let artifact: CodeArtifact
    private let languages: LanguageConfigurationResolver
    private let scope: CallGraphScope

    public init(
        artifact: CodeArtifact,
        languages: LanguageConfigurationResolver,
        scope: CallGraphScope = .wholeCodebase
    ) {
        self.artifact = artifact
        self.languages = languages
        self.scope = scope
    }

    public var report: Report {
        let graph = CallGraphBuilder(scope: scope).build(from: artifact)
        let targeted = Set(graph.edges.map(\.to))
        let allTypes = Array(artifact.flattened())
        let conformances = ConformanceIndex(artifact: artifact, types: allTypes)
        let nodeIdentity = CallGraphNodeIdentity(types: allTypes)

        var candidates: [Candidate] = []
        var scannedKinds: Set<MemberKind> = []
        for type in allTypes {
            let isContract = type.kind.isInterfaceLike
            // Each type is judged by *its own* language's configuration, so a polyglot artifact
            // doesn't apply one language's entry-point conventions or scanned kinds to another's.
            let configuration = languages.configuration(for: type)
            let markers = configuration.entryPointMarkers
            scannedKinds.formUnion(configuration.deadCodeMemberKinds)
            let supertypes = conformances.supertypes(of: type)
            for member in type.members where configuration.deadCodeMemberKinds.contains(member.kind) {
                let id = nodeIdentity.nodeID(for: member, in: type)
                guard !targeted.contains(id),
                      !conformances.isWitness(member, among: type.members, owedVia: supertypes),
                      !isEntryPoint(member, inContract: isContract, supertypes: supertypes.names, markers: markers)
                else { continue }
                candidates.append(Candidate(
                    id: id, typeName: nodeIdentity.nodeName(for: type), memberName: member.name,
                    location: member.location))
            }
        }
        let freestandingMarkers = languages.defaultConfiguration.entryPointMarkers
        if !artifact.freestandingFunctions.isEmpty { scannedKinds.insert(.method) }
        for function in artifact.freestandingFunctions where function.kind == .method {
            guard !targeted.contains(nodeIdentity.nodeID(forFreeFunction: function)),
                  !isEntryPoint(function, inContract: false, supertypes: [], markers: freestandingMarkers)
            else { continue }
            candidates.append(Candidate(
                id: nodeIdentity.nodeID(forFreeFunction: function), typeName: nil,
                memberName: function.name, location: function.location))
        }

        candidates.sort { $0.id < $1.id }
        return Report(
            coverage: graph.coverage,
            scannedKinds: MemberKind.allCases.filter(scannedKinds.contains),
            candidates: candidates)
    }

    /// A member is reachable-by-contract when it is public API, an abstract requirement (a body-less
    /// contract implemented by subtypes and reached polymorphically), overrides a supertype member, or
    /// is flagged by its language's entry-point `markers`.
    private func isEntryPoint(
        _ member: Member, inContract: Bool, supertypes: Set<String>, markers: EntryPointMarkers
    ) -> Bool {
        if inContract { return true }
        if member.isVisible(atLeast: .public) { return true }
        if member.modifiers.contains(.abstract) { return true }
        if member.modifiers.contains(.override) { return true }
        return markers.marks(member, inheritingFrom: supertypes)
    }
}

/// Supertypes and in-artifact protocol requirements keyed by resolved ``TypeID``, as enrichment canonicalises them.
private struct ConformanceIndex {
    /// `names` feed the language's conformance markers; `ids` look up in-artifact requirements.
    struct Supertypes {
        var names: Set<String> = []
        var ids: Set<TypeID> = []
    }

    /// Keyed on kind too, so an initializer requirement isn't witnessed by a same-named method.
    struct Requirement: Hashable {
        let kind: MemberKind
        let name: String
        let labels: [String?]

        init(_ member: Member) {
            kind = member.kind
            name = member.name
            labels = member.witnessLabels
        }
    }

    private let resolver: TypeIdentityResolver
    private let requirementsByProtocol: [TypeID: Set<Requirement>]
    private let supertypesByType: [TypeID: [String]]
    /// Lets a marker naming a bare `View` match a supertype the artifact declares as `MyUI.View`.
    private let simpleNames: [TypeID: String]

    /// The resolver is built from `artifact`'s top-level types; `types` is the flattened list the scan walks.
    init(artifact: CodeArtifact, types: [TypeDeclaration]) {
        let resolver = TypeIdentityResolver(types: artifact.types)
        var requirements: [TypeID: Set<Requirement>] = [:]
        var supertypes: [TypeID: [String]] = [:]
        var simpleNames: [TypeID: String] = [:]
        for type in types {
            let id = TypeID(type.id)
            simpleNames[id] = type.name
            supertypes[id] = type.inheritedTypes.map {
                resolver.canonicalName(for: $0.name, referencingModule: type.idScope.module)
            }
            guard type.kind.isInterfaceLike else { continue }
            requirements[id] = Set(type.members.map { Requirement($0) })
        }
        self.resolver = resolver
        requirementsByProtocol = requirements
        supertypesByType = supertypes
        self.simpleNames = simpleNames
    }

    /// Walks class supertypes too, since a subclass inherits the conformances its superclass declares.
    func supertypes(of type: TypeDeclaration) -> Supertypes {
        var result = Supertypes()
        var pending = supertypesByType[TypeID(type.id)] ?? []
        while let name = pending.popLast() {
            guard result.names.insert(name).inserted, let id = resolver.resolvedID(for: name),
                  result.ids.insert(id).inserted else { continue }
            if let simple = simpleNames[id] { result.names.insert(simple) }
            pending.append(contentsOf: supertypesByType[id] ?? [])
        }
        return result
    }

    /// Matches by labels so a same-named overload stays reportable, by name when no sibling matches.
    func isWitness(_ member: Member, among siblings: [Member], owedVia supertypes: Supertypes) -> Bool {
        let signature = Requirement(member)
        let owed = supertypes.ids.flatMap { requirementsByProtocol[$0] ?? [] }
            .filter { $0.kind == signature.kind && $0.name == signature.name }
        return owed.contains { requirement in
            requirement == signature || !siblings.contains { Requirement($0) == requirement }
        }
    }
}

private extension Member {
    var witnessLabels: [String?] {
        parameters.map { $0.externalName.flatMap { $0.isEmpty || $0 == "_" ? nil : $0 } }
    }
}

private extension TypeKind {
    /// Types whose declared methods are requirements callers reach through conformance, so their
    /// members are never "uncalled".
    var isInterfaceLike: Bool {
        self == .protocol || self == .interface || self == .trait
    }
}
