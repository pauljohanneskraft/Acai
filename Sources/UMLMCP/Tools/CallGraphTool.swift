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

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let scope = try resolvedCallGraphScope(arguments.string("scope"))
        return .json(try Value(CallGraphMetrics(artifact: artifact, scope: scope).report))
    }
}
