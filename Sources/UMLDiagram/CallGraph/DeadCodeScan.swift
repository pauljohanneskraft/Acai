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
    private let entryPoints: EntryPointMarkers
    private let scope: CallGraphScope

    public init(
        artifact: CodeArtifact,
        entryPoints: EntryPointMarkers = EntryPointMarkers(),
        scope: CallGraphScope = .wholeCodebase
    ) {
        self.artifact = artifact
        self.entryPoints = entryPoints
        self.scope = scope
    }

    public var report: Report {
        let graph = CallGraphBuilder(scope: scope).build(from: artifact)
        let targeted = Set(graph.edges.map(\.to))

        var candidates: [Candidate] = []
        for type in artifact.flattened() {
            let isContract = type.kind.isInterfaceLike
            for member in type.members where member.kind == .method {
                let id = "\(type.name).\(member.name)"
                guard !targeted.contains(id), !isEntryPoint(member, inContract: isContract) else { continue }
                candidates.append(Candidate(id: id, location: member.location))
            }
        }
        for function in artifact.freestandingFunctions where function.kind == .method {
            guard !targeted.contains(function.name), !isEntryPoint(function, inContract: false) else { continue }
            candidates.append(Candidate(id: function.name, location: function.location))
        }

        candidates.sort { $0.id < $1.id }
        return Report(coverage: graph.coverage, candidates: candidates)
    }

    /// A member is reachable-by-contract when it is public API, satisfies a supertype/interface
    /// requirement, or is flagged by a language entry-point marker.
    private func isEntryPoint(_ member: Member, inContract: Bool) -> Bool {
        if inContract { return true }
        if member.isVisible(atLeast: .public) { return true }
        if member.modifiers.contains(.override) { return true }
        return entryPoints.marks(member)
    }
}

private extension TypeKind {
    /// Types whose declared methods are requirements callers reach through conformance, so their
    /// members are never "uncalled".
    var isInterfaceLike: Bool {
        self == .protocol || self == .interface || self == .trait
    }
}
