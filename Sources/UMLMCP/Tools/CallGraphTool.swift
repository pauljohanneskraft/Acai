import MCP
import UMLLibrary

/// `uml_callgraph` — three cuts of the one static call graph, selected by `mode`: `metrics`
/// (per-method fan-in/out, recursion, coverage), `cycles` (method-level mutual-recursion clusters),
/// and `deadcode` (uncalled, non-entry-point candidates). Mirrors `uml callgraph --mode … --format json`.
struct CallGraphTool: AnalysisTool {
    let name = "uml_callgraph"
    let description = """
        Analyze the static call graph, three ways via 'mode': metrics (per-method fan-in/out, \
        recursion, resolution coverage — find hot methods), cycles (method-level mutual recursion / \
        tangled clusters), deadcode (uncalled methods not reachable by contract — public API, \
        overrides, protocol requirements, entry points; coverage is the false-positive floor). \
        metrics/cycles optionally scope with 'type:Name' or 'module:Name'.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "mode": [
                "type": "string",
                "enum": ["metrics", "cycles", "deadcode"],
                "description": "What to report: metrics (default), cycles, or deadcode."
            ],
            "scope": [
                "type": "string",
                "description": "Scope (metrics/cycles): 'type:Name' or 'module:Name'. Whole codebase if omitted."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        switch arguments.string("mode") ?? "metrics" {
        case "metrics":
            let scope = try resolvedCallGraphScope(arguments.string("scope"))
            return .json(try Value(CallGraphMetrics(artifact: artifact, scope: scope).report))
        case "cycles":
            let scope = try resolvedCallGraphScope(arguments.string("scope"))
            return .json(try Value(MethodCycles(artifact: artifact, scope: scope).clusters))
        case "deadcode":
            let report = DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver).report
            return .json(try Value(report))
        case let other:
            throw MCPError.invalidParams("mode must be metrics, cycles, or deadcode (got '\(other)').")
        }
    }
}
