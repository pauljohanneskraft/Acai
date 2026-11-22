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
            // Everything this type inherits from, transitively. Requirements it satisfies are
            // reached through the conformance, so never dead even without a direct call edge (the
            // witness analogue of `override`); the same names decide which framework members the
            // language's conformance-based markers exempt.
            let supertypes = conformances.supertypeNames(for: type)
            let requirements = conformances.requirements(inheritedVia: supertypes)
            for member in type.members where configuration.deadCodeMemberKinds.contains(member.kind) {
                let id = nodeIdentity.nodeID(for: member, in: type)
                guard !targeted.contains(id),
                      !isEntryPoint(
                        member, inContract: isContract, requirements: requirements,
                        supertypes: supertypes, markers: markers) else { continue }
                candidates.append(Candidate(
                    id: id, typeName: nodeIdentity.nodeName(for: type), memberName: member.name,
                    location: member.location))
            }
        }
        let freestandingMarkers = languages.defaultConfiguration.entryPointMarkers
        if !artifact.freestandingFunctions.isEmpty { scannedKinds.insert(.method) }
        for function in artifact.freestandingFunctions where function.kind == .method {
            guard !targeted.contains(nodeIdentity.nodeID(forFreeFunction: function)),
                  !isEntryPoint(
                    function, inContract: false, requirements: [],
                    supertypes: [], markers: freestandingMarkers) else { continue }
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
    /// contract implemented by subtypes and reached polymorphically), overrides a supertype member, is
    /// the witness for a protocol requirement its type conforms to, or is flagged by its language's
    /// entry-point `markers`.
    private func isEntryPoint(
        _ member: Member, inContract: Bool, requirements: Set<ConformanceIndex.Requirement>,
        supertypes: Set<String>, markers: EntryPointMarkers
    ) -> Bool {
        if inContract { return true }
        if member.isVisible(atLeast: .public) { return true }
        if member.modifiers.contains(.abstract) { return true }
        if member.modifiers.contains(.override) { return true }
        let signature = ConformanceIndex.Requirement(kind: member.kind, name: member.name)
        if requirements.contains(signature) { return true }
        return markers.marks(member, inheritingFrom: supertypes)
    }
}

/// The inheritance picture a dead-code verdict needs, resolved once per artifact: what each declared
/// type inherits from (transitively) and what requirements each in-artifact protocol declares.
///
/// Identity is the whole point. By the time the scan runs, `inheritedTypes[].name` has been rewritten
/// to a canonical type id by enrichment, so an index keyed on a simple name misses every supertype
/// whose id isn't its bare name — which, once a project is scoped by module, is all of them. Every
/// key here is a ``TypeID`` resolved through ``TypeIdentityResolver``, so a nested or
/// module-qualified protocol's witnesses are found like any other's.
///
/// Supertypes declared outside the analysed sources can't be inspected, so their requirements stay
/// unknown (surfaced as the usual coverage caveat); they are still reported by name, which is what a
/// language's conformance-based entry-point markers match on.
private struct ConformanceIndex {
    /// Keyed on kind as well as name: an initializer requirement is witnessed by an initializer, so a
    /// method that happens to share the name isn't mistaken for it. So a function-typed *property*
    /// requirement implemented as a method is not witnessed by that method; it only matters for a
    /// language whose contract members may be private.
    struct Requirement: Hashable {
        let kind: MemberKind
        let name: String
    }

    private let resolver: TypeIdentityResolver
    /// In-artifact interface-like type → the requirements it declares.
    private let requirementsByProtocol: [TypeID: Set<Requirement>]
    /// Declared type → the canonical names of the types it directly inherits.
    private let supertypesByType: [TypeID: [String]]
    /// Declared type → the simple name its source wrote, so a marker naming a bare `View` still
    /// matches a supertype the artifact declares as `MyUI.View`.
    private let simpleNames: [TypeID: String]

    /// `artifact` supplies the resolver, which recurses into nested types itself and so must be built
    /// from the top-level declarations; `types` is the already-flattened list the scan walks.
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
            requirements[id] = Set(type.members.map { Requirement(kind: $0.kind, name: $0.name) })
        }
        self.resolver = resolver
        requirementsByProtocol = requirements
        supertypesByType = supertypes
        self.simpleNames = simpleNames
    }

    /// Every supertype of `type`, transitively through the ones the artifact declares: each under its
    /// canonical name and, where the artifact declares it, its simple name too. A class supertype is
    /// walked like a protocol, since a subclass inherits the conformances its superclass declares.
    func supertypeNames(for type: TypeDeclaration) -> Set<String> {
        var result: Set<String> = []
        var pending = supertypesByType[TypeID(type.id)] ?? type.inheritedTypes.map {
            resolver.canonicalName(for: $0.name, referencingModule: type.idScope.module)
        }
        while let name = pending.popLast() {
            guard result.insert(name).inserted, let id = resolver.resolvedID(for: name) else { continue }
            if let simple = simpleNames[id] { result.insert(simple) }
            pending.append(contentsOf: supertypesByType[id] ?? [])
        }
        return result
    }

    /// The requirements a type owes to `supertypeNames`, its own transitive supertype closure. Names
    /// the artifact doesn't declare, and supertypes that aren't interface-like, contribute none.
    func requirements(inheritedVia supertypeNames: Set<String>) -> Set<Requirement> {
        var result: Set<Requirement> = []
        for name in supertypeNames {
            guard let id = resolver.resolvedID(for: name),
                  let declared = requirementsByProtocol[id] else { continue }
            result.formUnion(declared)
        }
        return result
    }
}

private extension TypeKind {
    /// Types whose declared methods are requirements callers reach through conformance, so their
    /// members are never "uncalled".
    var isInterfaceLike: Bool {
        self == .protocol || self == .interface || self == .trait
    }
}
