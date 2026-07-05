import MCP
import UMLLibrary

/// `uml_deadcode` — methods with no resolved callers that aren't reachable by contract, reported as
/// candidates alongside the call graph's coverage (the false-positive floor). Mirrors `uml deadcode`.
struct DeadCodeTool: AnalysisTool {
    let name = "uml_deadcode"
    let description = """
        List dead-code candidate methods: uncalled and not reachable by contract (public API, \
        overrides, protocol requirements, or a language entry point). Reports call-graph coverage as \
        the false-positive floor — treat results as candidates, not certainties.
        """

    var inputSchema: Value { objectSchema() }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> Value {
        let artifact = try await resolveArtifact(arguments, cache)
        let report = DeadCodeScan(
            artifact: artifact,
            entryPoints: artifact.standardLanguageConfiguration.entryPointMarkers).report
        return try Value(report)
    }
}
