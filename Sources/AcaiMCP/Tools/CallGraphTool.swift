import MCP
import AcaiLibrary

/// `acai_callgraph` — three cuts of the one static call graph, selected by `mode`: `metrics`
/// (per-method fan-in/out, recursion, coverage), `cycles` (method-level mutual-recursion clusters),
/// and `deadcode` (uncalled, non-entry-point candidates). Mirrors `acai callgraph --mode … --format json`.
struct CallGraphTool: AnalysisTool {
    let name = "acai_callgraph"
    let description = """
        Analyze the static call graph, three ways via 'mode': metrics (per-method fan-in/out, \
        recursion, resolution coverage — find hot methods), cycles (method-level mutual recursion / \
        tangled clusters), deadcode (uncalled members not reachable by contract — public API, \
        overrides, protocol requirements, entry points; methods in every language, plus a \
        language's initializers and subscripts where its parser records calls to them; the result's \
        scannedKinds lists the union of kinds scanned across every language in the codebase (not \
        necessarily all of them for a given language), and coverage is the false-positive floor). \
        metrics/cycles optionally scope with 'type:Name' or 'module:Name'.
        """

    var inputSchema: Value {
        var properties: [String: Value] = [
            "scope": [
                "type": "string",
                "description": "Scope (metrics/cycles): 'type:Name' or 'module:Name'. Whole codebase if omitted."
            ]
        ]
        properties.merge(EnumArgument<CallGraphMode>.mode.property) { $1 }
        properties.merge(generatedScopeProperty) { $1 }
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let mode = try EnumArgument<CallGraphMode>.mode.value(in: arguments, or: .metrics)
        let artifact = try await analysisArtifact(arguments, cache)
        let health = HealthCheck(artifact: artifact).summary
        switch mode {
        case .metrics:
            let scope = try resolvedCallGraphScope(arguments.string("scope"))
            let report = CallGraphMetrics(artifact: artifact, scope: scope).report
            return .json(try Value(MetricsPayload(callGraph: report, health: health)))
        case .cycles:
            let scope = try resolvedCallGraphScope(arguments.string("scope"))
            let clusters = MethodCycles(artifact: artifact, scope: scope).clusters
            return .json(try Value(CyclesPayload(cycles: clusters, health: health)))
        case .deadcode:
            let report = DeadCodeScan(artifact: artifact, languages: artifact.standardLanguageResolver).report
            return .json(try Value(DeadCodePayload(deadCode: report, health: health)))
        }
    }

    private struct MetricsPayload: Codable {
        var callGraph: CallGraphMetrics.Report
        var health: HealthCheck.Summary
    }

    private struct CyclesPayload: Codable {
        var cycles: [MethodCycles.Cluster]
        var health: HealthCheck.Summary
    }

    private struct DeadCodePayload: Codable {
        var deadCode: DeadCodeScan.Report
        var health: HealthCheck.Summary
    }
}
