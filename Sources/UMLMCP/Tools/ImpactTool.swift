import MCP
import UMLLibrary

/// `uml_impact` — the blast radius of a type: every type that transitively depends on it, so an agent
/// can answer "is this safe to change?" before touching it. Mirrors `uml impact <Type>`.
struct ImpactTool: AnalysisTool {
    let name = "uml_impact"
    let description = """
        Show the blast radius of a type: every type that transitively depends on it, with file:line. \
        Use before refactoring or deleting something to gauge whether the change is safe and what it \
        will ripple into.
        """

    var inputSchema: Value {
        objectSchema(
            extraProperties: [
                "type": [
                    "type": "string",
                    "description": "The type to analyze (simple name, qualified name, or id)."
                ],
                "depth": [
                    "type": "integer",
                    "description": "Limit reverse reachability to this many hops. Unlimited if omitted."
                ]
            ],
            required: ["path", "type"])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let report = ImpactAnalysis(
            artifact: artifact,
            rootType: try arguments.requiredString("type"),
            maxDepth: try arguments.int("depth")).report
        return .json(try Value(report))
    }
}
