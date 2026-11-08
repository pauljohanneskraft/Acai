import AcaiCore
import AcaiDiagram

/// The call graph's scope choice — whole codebase, one module or one type. Serves both the
/// creation-time sheet and the diagram sidebar, whose scope edit is staged and applied explicitly
/// because a new scope rebuilds the graph from scratch.
public struct CallGraphConfigModel: Sendable {
    public var scope: CallGraphScope

    /// Types that declare at least one method, which are the only ones a call graph can be scoped to.
    public let typeNames: [String]
    public let moduleNames: [String]

    public init(
        artifact: CodeArtifact,
        initial: CallGraphScope = .wholeCodebase,
        walkObserver: AnalysisWalkObserver? = nil
    ) {
        let lookups = CallGraphScopeLookups(artifact: artifact)
        walkObserver?.didWalk()
        scope = initial
        typeNames = lookups.typeNames
        moduleNames = lookups.moduleNames
    }
}

/// Both scope option lists, derived in one pass over the analysis. The pickers read these on each
/// render, and the module list rebuilt a whole `ModuleMap` each time.
private struct CallGraphScopeLookups {
    let typeNames: [String]
    let moduleNames: [String]

    init(artifact: CodeArtifact) {
        let modules = ModuleMap(artifact: artifact)
        var types: [String] = []
        var moduleNames: [String] = []
        for type in artifact.types {
            if type.members.contains(where: { $0.kind == .method }) { types.append(type.name) }
            moduleNames.append(modules.module(forFilePath: type.location?.filePath ?? ""))
        }
        typeNames = types.uniqued().sorted()
        self.moduleNames = moduleNames.uniqued().sorted()
    }
}
