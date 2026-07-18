import MCP
import AcaiLibrary

/// `acai_diff` — the structural delta between two revisions of a codebase: added/removed types,
/// added/removed/changed relationships, and notable metric movement. Mirrors `acai diff --format json`.
/// Each side is a source directory to analyze or a `.json` artifact baseline (both go through the
/// shared snapshot cache).
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
            "properties": .object([
                "pathOld": [
                    "type": "string",
                    "description": "Old side: a source directory to analyze, or a .json artifact baseline."
                ],
                "pathNew": [
                    "type": "string",
                    "description": "New side: a source directory to analyze, or a .json artifact baseline."
                ],
                "languages": [
                    "type": "array", "items": ["type": "string"],
                    "description": "Optional language filter for directory sides. Empty means all."
                ],
                "refresh": [
                    "type": "boolean",
                    "description": "Re-analyze instead of reusing a cached snapshot for either side."
                ]
            ]),
            "required": ["pathOld", "pathNew"]
        ]
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let languages = arguments.stringArray("languages")
        let refresh = try arguments.bool("refresh") ?? false
        let old = try await cache.artifact(
            path: try arguments.requiredString("pathOld"), languageNames: languages, refresh: refresh)
        let new = try await cache.artifact(
            path: try arguments.requiredString("pathNew"), languageNames: languages, refresh: refresh)
        return .json(try Value(ArtifactDiffer().diff(old: old, new: new)))
    }
}
