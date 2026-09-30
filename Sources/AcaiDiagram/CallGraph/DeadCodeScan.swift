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
        public var id: String
        public var location: SourceLocation?
    }

    public struct Report: Codable, Hashable, Sendable {
        /// The call graph's resolution coverage — the false-positive floor for `candidates`.
        public var coverage: CallGraph.Coverage
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
        let witnesses = ProtocolWitnessIndex(types: allTypes)
        let nodeIdentity = CallGraphNodeIdentity(types: allTypes)

        var candidates: [Candidate] = []
        for type in allTypes {
            let isContract = type.kind.isInterfaceLike
            // Each type is judged by *its own* language's configuration, so a polyglot artifact
            // doesn't apply one language's entry-point conventions or scanned kinds to another's.
            let configuration = languages.configuration(for: type)
            let markers = configuration.entryPointMarkers
            // Protocol requirements this type satisfies — reached through the conformance, so never
            // dead even without a direct call edge (the witness analogue of `override`).
            let requirements = witnesses.requirements(for: type)
            for member in type.members where configuration.deadCodeMemberKinds.contains(member.kind) {
                let id = "\(nodeIdentity.nodeName(for: type)).\(member.name)"
                guard !targeted.contains(id),
                      !isEntryPoint(
                        member, inContract: isContract,
                        requirements: requirements, markers: markers) else { continue }
                candidates.append(Candidate(id: id, location: member.location))
            }
        }
        let freestandingMarkers = languages.defaultConfiguration.entryPointMarkers
        for function in artifact.freestandingFunctions where function.kind == .method {
            guard !targeted.contains(function.name),
                  !isEntryPoint(
                    function, inContract: false,
                    requirements: [], markers: freestandingMarkers) else { continue }
            candidates.append(Candidate(id: function.name, location: function.location))
        }

        candidates.sort { $0.id < $1.id }
        return Report(coverage: graph.coverage, candidates: candidates)
    }

    /// A member is reachable-by-contract when it is public API, an abstract requirement (a body-less
    /// contract implemented by subtypes and reached polymorphically), overrides a supertype member, is
    /// the witness for a protocol requirement its type conforms to, or is flagged by its language's
    /// entry-point `markers`.
    private func isEntryPoint(
        _ member: Member, inContract: Bool,
        requirements: Set<ProtocolWitnessIndex.Requirement>, markers: EntryPointMarkers
    ) -> Bool {
        if inContract { return true }
        if member.isVisible(atLeast: .public) { return true }
        if member.modifiers.contains(.abstract) { return true }
        if member.modifiers.contains(.override) { return true }
        let signature = ProtocolWitnessIndex.Requirement(kind: member.kind, name: member.name)
        if requirements.contains(signature) { return true }
        return markers.marks(member)
    }
}

/// Resolves, per conforming type, the member requirements of every in-artifact protocol it conforms
/// to — transitively through protocol inheritance. A member matching one is a *witness*: a caller
/// reaches it through the conformance, so it is never dead even when no direct call edge targets it.
/// Protocols defined outside the analysed sources can't be inspected, so their witnesses stay
/// best-effort (surfaced as the usual coverage caveat).
private struct ProtocolWitnessIndex {
    /// Keyed on kind as well as name: an initializer requirement is witnessed by an initializer, so a
    /// method that happens to share the name isn't mistaken for it.
    struct Requirement: Hashable {
        let kind: MemberKind
        let name: String
    }

    /// Interface-like type name → its own requirements.
    private let requirementsByProtocol: [String: Set<Requirement>]
    /// Interface-like type name → the names of the protocols it refines.
    private let refinementsByProtocol: [String: [String]]

    init(types: [TypeDeclaration]) {
        var requirements: [String: Set<Requirement>] = [:]
        var refinements: [String: [String]] = [:]
        for type in types where type.kind.isInterfaceLike {
            requirements[type.name] = Set(type.members.map { Requirement(kind: $0.kind, name: $0.name) })
            refinements[type.name] = type.inheritedTypes.map(\.name)
        }
        requirementsByProtocol = requirements
        refinementsByProtocol = refinements
    }

    func requirements(for type: TypeDeclaration) -> Set<Requirement> {
        var result: Set<Requirement> = []
        var pending = type.inheritedTypes.map(\.name)
        var seen: Set<String> = []
        while let name = pending.popLast() {
            guard requirementsByProtocol[name] != nil, seen.insert(name).inserted else { continue }
            result.formUnion(requirementsByProtocol[name] ?? [])
            pending.append(contentsOf: refinementsByProtocol[name] ?? [])
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
