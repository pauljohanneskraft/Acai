import MCP
import AcaiLibrary

/// `acai_diff` — the structural delta between two revisions of a codebase. Mirrors
/// `acai diff --format json`. Each side is a source directory to analyze or a `.json` artifact baseline.
struct DiffTool: AnalysisTool {
    let name = "acai_diff"
    let description = """
        Show the structural delta between two revisions of a codebase (added/removed types, changed \
        relationships, metric movement). Each side is a source directory or a .json artifact baseline. \
        Use to review what a change altered, or to gate drift against a baseline.
        """

    var inputSchema: Value {
        [
            "type": "object",
            "properties": .object(LanguageListArgument.diffLanguages.property.merging([
                "pathOld": [
                    "type": "string",
                    "description": "Old side: a source directory to analyze, or a .json artifact baseline."
                ],
                "pathNew": [
                    "type": "string",
                    "description": "New side: a source directory to analyze, or a .json artifact baseline."
                ],
                "refresh": [
                    "type": "boolean",
                    "description": "Re-analyze instead of reusing a cached snapshot for either side."
                ]
            ]) { $1 }),
            "required": ["pathOld", "pathNew"]
        ]
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let languages = try LanguageListArgument.diffLanguages.values(in: arguments)
        let refresh = try arguments.bool("refresh") ?? false
        let old = try await cache.artifact(
            path: try arguments.requiredString("pathOld"), languageNames: languages, refresh: refresh)
        let new = try await cache.artifact(
            path: try arguments.requiredString("pathNew"), languageNames: languages, refresh: refresh)
        let diff = ArtifactDiffer().diff(old: old, new: new)
        let health = HealthCheck(artifact: old).summary.combined(with: HealthCheck(artifact: new).summary)
        return .json(try Value(Payload(diff: diff, health: health)))
    }

    private struct Payload: Codable {
        var diff: ArtifactDiff
        var health: HealthCheck.Summary
    }
}
