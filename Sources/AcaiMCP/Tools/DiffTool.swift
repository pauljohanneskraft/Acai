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
        var properties = LanguageListArgument.diffLanguages.property.merging([
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
        ]) { $1 }
        properties.merge(generatedScopeProperty) { $1 }
        return [
            "type": "object",
            "properties": .object(properties),
            "required": ["pathOld", "pathNew"]
        ]
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let languages = try LanguageListArgument.diffLanguages.values(in: arguments)
        let refresh = try arguments.bool("refresh") ?? false
        let oldPath = try arguments.requiredString("pathOld")
        let newPath = try arguments.requiredString("pathNew")
        let old = try generatedScoped(
            await cache.artifact(path: oldPath, languageNames: languages, refresh: refresh), arguments)
        let new = try generatedScoped(
            await cache.artifact(path: newPath, languageNames: languages, refresh: refresh), arguments)
        let diff = ArtifactDiffer().diff(old: old, new: new)
        let health = HealthCheck(artifact: old).summary.combined(with: HealthCheck(artifact: new).summary)
        return .json(try Value(Payload(diff: diff, health: health)))
    }

    private struct Payload: Codable {
        var diff: ArtifactDiff
        var health: HealthCheck.Summary
    }
}
