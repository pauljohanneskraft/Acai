import UMLCore

/// Methods that no resolved call edge targets and that aren't reachable by contract — dead-code
/// *candidates*. Because call resolution is best-effort, the report always carries the call graph's
/// `coverage`: the lower the coverage, the more of these are false positives (a real caller the parser
/// couldn't resolve), so a consumer reads them as leads, not verdicts.
///
/// A value you instantiate over an artifact plus the language's `EntryPointMarkers`
/// (`DeadCodeScan(artifact:entryPoints:).report`). The universal reachability rules (public API,
/// `override`, protocol/interface requirements) are applied here; the language-specific test/framework
/// markers come from the injected configuration, so this names no language.
public struct DeadCodeScan: Sendable {
    /// A method that might be unused.
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

        var candidates: [Candidate] = []
        for type in allTypes {
            let isContract = type.kind.isInterfaceLike
            // Each type's entry-point markers come from *its own* language, so a polyglot artifact
            // doesn't judge one language's methods by another's entry-point conventions.
            let markers = languages.configuration(for: type).entryPointMarkers
            // Names of protocol requirements this type satisfies — reached through the conformance,
            // so never dead even without a direct call edge (the witness analogue of `override`).
            let requirementNames = witnesses.requirementNames(for: type)
            for member in type.members where member.kind == .method {
                let id = "\(type.name).\(member.name)"
                guard !targeted.contains(id),
                      !isEntryPoint(
                        member, inContract: isContract,
                        requirementNames: requirementNames, markers: markers) else { continue }
                candidates.append(Candidate(id: id, location: member.location))
            }
        }
        let freestandingMarkers = languages.defaultConfiguration.entryPointMarkers
        for function in artifact.freestandingFunctions where function.kind == .method {
            guard !targeted.contains(function.name),
                  !isEntryPoint(
                    function, inContract: false,
                    requirementNames: [], markers: freestandingMarkers) else { continue }
            candidates.append(Candidate(id: function.name, location: function.location))
        }

        candidates.sort { $0.id < $1.id }
        return Report(coverage: graph.coverage, candidates: candidates)
    }

    /// A member is reachable-by-contract when it is public API, overrides a supertype member, is the
    /// witness for a protocol requirement its type conforms to, or is flagged by its language's
    /// entry-point `markers`.
    private func isEntryPoint(
        _ member: Member, inContract: Bool, requirementNames: Set<String>, markers: EntryPointMarkers
    ) -> Bool {
        if inContract { return true }
        if member.isVisible(atLeast: .public) { return true }
        if member.modifiers.contains(.override) { return true }
        if requirementNames.contains(member.name) { return true }
        return markers.marks(member)
    }
}

/// Resolves, per conforming type, the method-requirement names of every in-artifact protocol it
/// conforms to — transitively through protocol inheritance. A method whose name matches one is a
/// *witness*: a caller reaches it through the conformance, so it is never dead even when no direct
/// call edge targets it. Protocols defined outside the analysed sources can't be inspected, so their
/// witnesses stay best-effort (surfaced as the usual coverage caveat).
private struct ProtocolWitnessIndex {
    /// Interface-like type name → the names of its own method requirements.
    private let requirementsByProtocol: [String: Set<String>]
    /// Interface-like type name → the names of the protocols it refines.
    private let refinementsByProtocol: [String: [String]]

    init(types: [TypeDeclaration]) {
        var requirements: [String: Set<String>] = [:]
        var refinements: [String: [String]] = [:]
        for type in types where type.kind.isInterfaceLike {
            requirements[type.name] = Set(type.members.filter { $0.kind == .method }.map(\.name))
            refinements[type.name] = type.inheritedTypes.map(\.name)
        }
        requirementsByProtocol = requirements
        refinementsByProtocol = refinements
    }

    func requirementNames(for type: TypeDeclaration) -> Set<String> {
        var result: Set<String> = []
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
