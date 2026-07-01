import ArgumentParser
import Foundation
import UMLDiagram
import UMLLibrary

// Shared diagram-model construction for the `diagram`, `image`, and `diff` commands. Each command
// used to inline the same builder calls, entry-point/scope parsing, and emptiness validation, which
// made all three fan-out outliers and let the rules drift between them. These request value types
// own that logic once; a command constructs the request from its flags and asks for a model.

/// The `--call-graph-scope` flag (`"type:Name"` / `"module:Name"`), parsed on demand.
struct CallGraphScopeOption {
    /// The raw flag value, or `nil` for the whole codebase.
    let raw: String?

    /// Resolves the raw value into a `CallGraphScope`, throwing a `ValidationError` on a malformed
    /// value (matches the message the three commands previously emitted).
    func resolved() throws -> CallGraphScope {
        guard let raw else { return .wholeCodebase }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw ValidationError("--call-graph-scope must be \"type:Name\" or \"module:Name\".")
        }
        switch parts[0] {
        case "type":
            return .type(parts[1])
        case "module":
            return .module(parts[1])
        default:
            throw ValidationError("--call-graph-scope must start with \"type:\" or \"module:\".")
        }
    }

    /// The human-readable diagram title for this scope (used by the standalone `diagram` render path;
    /// the diff/image paths leave the call graph untitled).
    func title() throws -> String {
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
struct SequenceDiagramRequest {
    /// Raw `--sequence-from` value (`"Type.method"` or a bare top-level function name).
    let entryPoint: String
    let maxDepth: Int
    /// Raw `--map` entries (`"Protocol=Concrete"`); empty when the command has no such flag.
    var map: [String] = []

    /// Parses `--map` into an interface→concrete lookup, throwing on a malformed entry.
    func typeMapping() throws -> [String: String] {
        var mapping: [String: String] = [:]
        for entry in map {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw ValidationError("--map must be in the form \"Protocol=Concrete\".")
            }
            mapping[parts[0]] = parts[1]
        }
        return mapping
    }

    /// Builds the diagram model (no emptiness check — used by the diff path, which compares two).
    func build(from artifact: CodeArtifact) throws -> SequenceDiagram {
        let entry = try parseSequenceEntryPoint(entryPoint)
        let mapping = try typeMapping()
        return SequenceDiagramBuilder(entryPoint: entry, maxDepth: maxDepth, typeMapping: mapping)
            .build(from: artifact)
    }

    /// Builds the diagram and fails if nothing could be traced (single-diagram rendering paths).
    func buildTraceable(from artifact: CodeArtifact) throws -> SequenceDiagram {
        let diagram = try build(from: artifact)
        guard !diagram.participants.isEmpty else {
            throw ValidationError(
                "No calls could be traced from \(entryPoint). Sequence diagrams follow "
                + "explicitly-typed property receivers; try another entry point or --map."
            )
        }
        return diagram
    }
}

/// Runs the value-flow state analysis for a variable, mapping analysis errors to `ValidationError`.
struct StateDiagramRequest {
    /// Raw `--state-from` value (`"Type.variable"` or a bare global name).
    let variable: String
    let maxStates: Int

    func build(from artifact: CodeArtifact) throws -> StateDiagram {
        let configuration = try StateDiagramConfiguration(stateFrom: variable, maxStates: maxStates)
        do {
            return try StateDiagramBuilder(configuration: configuration)
                .build(from: artifact.resolvingExtensions())
        } catch let error as StateDiagramAnalysisError {
            throw ValidationError(error.message)
        }
    }
}

/// Builds a static call graph for an optional scope.
struct CallGraphRequest {
    let scope: CallGraphScopeOption
    /// Optional diagram title (set by the standalone `diagram` path; `nil` for diff/image).
    var title: String?

    init(scope: CallGraphScopeOption, title: String? = nil) {
        self.scope = scope
        self.title = title
    }

    /// Builds the graph (no emptiness check — used by the diff path, which compares two).
    func build(from artifact: CodeArtifact) throws -> CallGraph {
        CallGraphBuilder(scope: try scope.resolved(), title: title).build(from: artifact)
    }

    /// Builds the graph and fails if no calls resolved (single-diagram rendering paths). A node-only
    /// graph is not a useful diagram, so it is treated as "nothing to draw".
    func buildWithEdges(from artifact: CodeArtifact) throws -> CallGraph {
        let graph = try build(from: artifact)
        guard !graph.edges.isEmpty else {
            throw ValidationError(
                "No resolvable calls found for the requested scope. Call graphs follow "
                + "explicitly-typed call receivers; try a wider scope or another language."
            )
        }
        return graph
    }
}

/// Builds the package/module dependency diagram for an artifact (enriching it first, as every
/// package path requires).
struct PackageDiagramRequest {
    func build(from artifact: CodeArtifact) -> PackageDiagram {
        PackageDiagramBuilder().build(
            from: artifact.enriched(configuration: artifact.standardLanguageConfiguration))
    }
}
