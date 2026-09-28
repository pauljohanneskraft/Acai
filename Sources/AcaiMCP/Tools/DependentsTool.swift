import MCP
import AcaiLibrary

/// `acai_dependents` — the blast radius of a type. Mirrors `acai dependents <Type>`.
struct DependentsTool: AnalysisTool {
    let name = "acai_dependents"
    let description = """
        Show the blast radius of a type: every type that transitively depends on it, with file:line. \
        Use before refactoring or deleting something to gauge whether the change is safe and what it \
        will ripple into.
        """

    var inputSchema: Value {
        var properties: [String: Value] = [
            "type": [
                "type": "string",
                "description": "The type to analyze (simple name, qualified name, or id)."
            ],
            "depth": [
                "type": "integer",
                "description": "Limit reverse reachability to this many hops. Unlimited if omitted."
            ]
        ]
        properties.merge(generatedScopeProperty) { $1 }
        return objectSchema(extraProperties: properties, required: ["path", "type"])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await analysisArtifact(arguments, cache)
        let report = ImpactAnalysis(
            artifact: artifact,
            rootType: try arguments.requiredString("type"),
            maxDepth: try arguments.int("depth")).report
        let payload = Payload(impact: report, health: HealthCheck(artifact: artifact).summary)
        return .json(try Value(payload))
    }

    /// The `impact` key is the published output shape, so it outlives the tool's old name.
    private struct Payload: Codable {
        var impact: ImpactAnalysis.Report
        var health: HealthCheck.Summary
    }
}

/// `acai_impact` — deprecated alias for ``DependentsTool``, left out of `tools/list` so no existing
/// agent configuration breaks. Remove in the next major release.
struct ImpactTool: AnalysisTool {
    let name = "acai_impact"
    let isDeprecatedAlias = true

    private let dependents = DependentsTool()

    var description: String { dependents.description }
    var inputSchema: Value { dependents.inputSchema }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        try await dependents.run(arguments: arguments, cache: cache)
    }
}
