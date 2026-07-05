import MCP
import UMLLibrary

/// `uml_metrics` — the full static-analysis metric set (counts, per-module coupling/instability,
/// per-type OO metrics and smell scores). Mirrors `uml metrics --format json`.
struct MetricsTool: AnalysisTool {
    let name = "uml_metrics"
    let description = """
        Compute static-analysis metrics: per-module coupling and instability, and per-type fan-in/out, \
        weighted methods, inheritance depth, cohesion (LCOM) and data-class scores. Use to find god \
        classes and coupling hotspots when planning a refactor.
        """

    var inputSchema: Value { objectSchema() }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let metrics = try await resolveArtifact(arguments, cache).computeMetrics()
        return .json(try Value(metrics))
    }
}
