import MCP
import UMLLibrary

/// `uml_analyze` — index a project once and return a compact snapshot summary (not the full model,
/// which is too large for context). Populates the shared cache so every other tool reuses this parse.
struct AnalyzeTool: AnalysisTool {
    let name = "uml_analyze"
    let description = """
        Index a codebase for structural analysis and return a summary (languages, type/relationship \
        counts, parse-health score). Call this first when starting to reason about an unfamiliar or \
        large project; the other uml_* tools reuse the cached parse. Set 'health' for the full \
        parse-health report (diagnostics with file:line) — run it before trusting the other tools, \
        since a low score means metrics and cycles built on this parse are unreliable.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "health": [
                "type": "boolean",
                "description": "Return the full parse-health report (a trust score + diagnostics) instead."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let health = HealthCheck(artifact: artifact).report
        if try arguments.bool("health") ?? false {
            return .json(try Value(health))
        }
        let snapshot = Snapshot(
            path: try arguments.requiredString("path"),
            language: artifact.metadata.sourceLanguage.rawValue,
            fileCount: artifact.metadata.filePaths.count,
            typeCount: artifact.flattened().count,
            relationshipCount: artifact.relationships.count,
            parseHealthScore: health.score,
            hasParseErrors: artifact.metadata.hasParseErrors)
        return .json(try Value(snapshot))
    }

    private struct Snapshot: Codable {
        var path: String
        var language: String
        var fileCount: Int
        var typeCount: Int
        var relationshipCount: Int
        var parseHealthScore: Double
        var hasParseErrors: Bool
    }
}
