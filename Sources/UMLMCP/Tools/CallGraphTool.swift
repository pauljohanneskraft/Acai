import MCP
import UMLLibrary

/// `uml_callgraph` — the static call graph as metrics rather than a diagram: per-method fan-in/out,
/// recursion, and resolution coverage. Mirrors `uml callgraph --format json`.
struct CallGraphTool: AnalysisTool {
    let name = "uml_callgraph"
    let description = """
        Report the static call graph as metrics: per-method fan-in/out, recursion, and the graph's \
        resolution coverage. Use to find hot methods and understand method-level structure. Optionally \
        scope with 'type:Name' or 'module:Name'.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "scope": [
                "type": "string",
                "description": "Scope: 'type:Name' or 'module:Name'. Whole codebase if omitted."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> Value {
        let artifact = try await resolveArtifact(arguments, cache)
        let report = CallGraphMetrics(artifact: artifact, scope: try scope(from: arguments.string("scope"))).report
        return try Value(report)
    }

    /// Parses the `scope` string into a `CallGraphScope`; whole-codebase when absent.
    private func scope(from raw: String?) throws -> CallGraphScope {
        guard let raw, !raw.isEmpty else { return .wholeCodebase }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else {
            throw MCPError.invalidParams("scope must be 'type:Name' or 'module:Name'.")
        }
        switch parts[0] {
        case "type":
            return .type(parts[1])
        case "module":
            return .module(parts[1])
        default:
            throw MCPError.invalidParams("scope prefix must be 'type' or 'module'.")
        }
    }
}
