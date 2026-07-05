import MCP
import UMLLibrary

/// `uml_doctor` — parse health as a trust score over parse diagnostics. A low score means the rest of
/// an audit built on this artifact is untrustworthy, so it's the guardrail to run first. Mirrors
/// `uml doctor --format json`.
struct DoctorTool: AnalysisTool {
    let name = "uml_doctor"
    let description = """
        Report parse health as a trust score (0–1) over parse diagnostics, with the offending \
        file:line locations. Run this before trusting the other tools: a low score means large parts \
        of the codebase did not parse cleanly, so metrics and cycles built on it are unreliable.
        """

    var inputSchema: Value { objectSchema() }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let report = HealthCheck(artifact: try await resolveArtifact(arguments, cache)).report
        return .json(try Value(report))
    }
}
