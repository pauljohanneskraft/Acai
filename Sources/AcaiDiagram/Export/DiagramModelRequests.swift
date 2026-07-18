import AcaiCore

// Shared diagram-model construction for every front end (the `diagram`/`image`/`diff` CLI commands and
// the MCP's diagram/image tools). Each request value owns the builder call, scope/entry-point parsing,
// and emptiness validation once — so the rules can't drift between consumers. Promoted here from the
// CLI (which used to inline them); front ends map `DiagramRequestError` onto their own error surface.

/// A call-graph scope (`"type:Name"` / `"module:Name"`), parsed on demand.
public struct CallGraphScopeOption: Sendable {
    /// The raw value, or `nil` for the whole codebase.
    public let raw: String?

    public init(raw: String?) {
        self.raw = raw
    }

    /// Resolves the raw value into a `CallGraphScope`, throwing on a malformed value.
    public func resolved() throws -> CallGraphScope {
        guard let raw else { return .wholeCodebase }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw DiagramRequestError("scope must be \"type:Name\" or \"module:Name\".")
        }
        switch parts[0] {
        case "type":
            return .type(parts[1])
        case "module":
            return .module(parts[1])
        default:
            throw DiagramRequestError("scope must start with \"type:\" or \"module:\".")
        }
    }

    /// The human-readable diagram title for this scope (the standalone diagram render path uses it;
    /// the diff/image paths leave the call graph untitled).
    public func title() throws -> String {
        switch try resolved() {
        case .wholeCodebase:
            return "Call graph"
        case .type(let name):
            return "Call graph — \(name)"
        case .module(let name):
            return "Call graph — \(name) module"
        }
    }
}

/// Builds a sequence diagram traced from an entry point, with optional interface→concrete mapping.
public struct SequenceDiagramRequest: Sendable {
    /// Raw entry-point value (`"Type.method"` or a bare top-level function name).
    public let entryPoint: String
    public let maxDepth: Int
    /// Raw `Protocol=Concrete` mapping entries; empty when the front end has no such option.
    public let map: [String]

    public init(entryPoint: String, maxDepth: Int, map: [String] = []) {
        self.entryPoint = entryPoint
        self.maxDepth = maxDepth
        self.map = map
    }

    /// Parses the mapping entries into an interface→concrete lookup, throwing on a malformed entry.
    public func typeMapping() throws -> [String: String] {
        var mapping: [String: String] = [:]
        for entry in map {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw DiagramRequestError("type mapping must be in the form \"Protocol=Concrete\".")
            }
            mapping[parts[0]] = parts[1]
        }
        return mapping
    }

    /// Builds the diagram model (no emptiness check — used by the diff path, which compares two).
    public func build(from artifact: CodeArtifact) throws -> SequenceDiagram {
        let entry = try SequenceEntryPoint(parsing: entryPoint)
        let mapping = try typeMapping()
        return SequenceDiagramBuilder(entryPoint: entry.components, maxDepth: maxDepth, typeMapping: mapping)
            .build(from: artifact)
    }

    /// Builds the diagram and fails if nothing could be traced (single-diagram rendering paths).
    public func buildTraceable(from artifact: CodeArtifact) throws -> SequenceDiagram {
        let diagram = try build(from: artifact)
        guard !diagram.participants.isEmpty else {
            throw DiagramRequestError(
                "No calls could be traced from \(entryPoint). Sequence diagrams follow "
                + "explicitly-typed property receivers; try another entry point or a type mapping."
            )
        }
        return diagram
    }
}

/// Runs the value-flow state analysis for a variable, mapping analysis errors to `DiagramRequestError`.
public struct StateDiagramRequest: Sendable {
    /// Raw variable value (`"Type.variable"` or a bare global name).
    public let variable: String
    public let maxStates: Int

    public init(variable: String, maxStates: Int) {
        self.variable = variable
        self.maxStates = maxStates
    }

    public func build(from artifact: CodeArtifact) throws -> StateDiagram {
        let configuration = try StateDiagramConfiguration(stateFrom: variable, maxStates: maxStates)
        do {
            return try StateDiagramBuilder(configuration: configuration)
                .build(from: artifact.resolvingExtensions())
        } catch let error as StateDiagramAnalysisError {
            throw DiagramRequestError(error.message)
        }
    }
}

/// Builds a static call graph for an optional scope.
public struct CallGraphRequest: Sendable {
    public let scope: CallGraphScopeOption
    /// Optional diagram title (set by the standalone diagram path; `nil` for diff/image).
    public let title: String?

    public init(scope: CallGraphScopeOption, title: String? = nil) {
        self.scope = scope
        self.title = title
    }

    /// Builds the graph (no emptiness check — used by the diff path, which compares two).
    public func build(from artifact: CodeArtifact) throws -> CallGraph {
        CallGraphBuilder(scope: try scope.resolved(), title: title).build(from: artifact)
    }

    /// Builds the graph and fails if no calls resolved (single-diagram rendering paths). A node-only
    /// graph is not a useful diagram, so it is treated as "nothing to draw".
    public func buildWithEdges(from artifact: CodeArtifact) throws -> CallGraph {
        let graph = try build(from: artifact)
        guard !graph.edges.isEmpty else {
            throw DiagramRequestError(
                "No resolvable calls found for the requested scope. Call graphs follow "
                + "explicitly-typed call receivers; try a wider scope or another language."
            )
        }
        return graph
    }
}

/// Builds the package/module dependency diagram for an artifact. The caller injects the artifact's
/// `LanguageConfigurationResolver` (the package path enriches first, per type) — keeping this agnostic:
/// it names no language, it is handed one.
public struct PackageDiagramRequest: Sendable {
    public init() {}

    public func build(from artifact: CodeArtifact, languages: LanguageConfigurationResolver) -> PackageDiagram {
        PackageDiagramBuilder().build(from: artifact.enriched(using: languages))
    }
}
