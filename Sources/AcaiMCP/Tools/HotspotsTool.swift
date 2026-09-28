// Churn is a git-history walk via `AcaiGit` (libgit2), linked into the MCP server on macOS only —
// the same gating `acai_image`/`AcaiRender` uses.
#if os(macOS)
import Foundation
import MCP
import AcaiGit
import AcaiLibrary
import AcaiQuality

/// `acai_hotspots` — the ranked churn × complexity list. Mirrors `acai hotspots --format json`.
struct HotspotsTool: AnalysisTool {
    let name = "acai_hotspots"
    let description = """
        Rank a codebase's files by churn × complexity: how often a file changes against how complex \
        its types are. Use to decide where a refactoring budget pays off most, or which files a risky \
        change is likeliest to touch. Needs a git checkout with history. macOS only.
        """

    var inputSchema: Value {
        var properties: [String: Value] = [
            "commits": [
                "type": "integer",
                "description": "How many commits of history to walk for churn (default 50)."
            ],
            "top": ["type": "integer", "description": "Limit the report to the top N hotspots."]
        ]
        properties.merge(generatedScopeProperty) { $1 }
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let path = try arguments.requiredString("path")
        let commits = try arguments.int("commits") ?? 50
        guard commits > 0 else { throw MCPError.invalidParams("'commits' must be at least 1.") }
        let top = try arguments.int("top")
        if let top, top < 1 { throw MCPError.invalidParams("'top' must be at least 1.") }

        let churn = try churnByFile(at: URL(fileURLWithPath: path).standardizedFileURL, limit: commits)
        let artifact = try await analysisArtifact(arguments, cache)
        let payload = Payload(
            hotspots: Hotspots(artifact: artifact, churnByFile: churn), commitWindow: commits, top: top)
        return .json(try Value(payload))
    }

    /// Churn is the whole point of the report, so "no history here" is a named failure rather than a
    /// ranked list that is silently empty.
    private func churnByFile(at url: URL, limit: Int) throws -> [String: Int] {
        do {
            guard let churn = try DirectoryChurn(directory: url).byFile(limit: limit) else {
                throw MCPError.invalidParams(
                    "\(url.path) is not inside a git checkout. Hotspots rank files by how often they change "
                    + "against how complex they are, so they need a repository with commit history."
                )
            }
            return churn
        } catch is HistoryNotFetched {
            throw MCPError.invalidParams(
                "\(url.path) is a shallow clone, so only the commits it happens to hold could be counted. "
                + "Run `git fetch --unshallow` there first."
            )
        }
    }

    private struct Payload: Codable {
        var churnThreshold: Double
        var complexityThreshold: Double
        var commitWindow: Int
        var filesScored: Int
        var hotspots: [Hotspots.File]

        init(hotspots: Hotspots, commitWindow: Int, top: Int?) {
            churnThreshold = hotspots.churnThreshold
            complexityThreshold = hotspots.complexityThreshold
            self.commitWindow = commitWindow
            filesScored = hotspots.files.count
            let ranked = hotspots.ranked
            self.hotspots = top.map { Array(ranked.prefix($0)) } ?? ranked
        }
    }
}
#endif
