import MCP
import UMLLibrary

/// `uml_cycles` — dependency cycles (strongly-connected components) at module and/or type scope.
/// Mirrors `uml cycles --format json`.
struct CyclesTool: AnalysisTool {
    let name = "uml_cycles"
    let description = """
        Detect dependency cycles (strongly-connected components) between modules and/or types — the \
        tangles that make a codebase hard to change safely. Scope with 'modules', 'types', or 'all'.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "scope": [
                "type": "string",
                "enum": ["modules", "types", "all"],
                "description": "Cycle scope: modules, types, or all (default)."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> Value {
        let artifact = try await resolveArtifact(arguments, cache)
        let finder = CycleFinder(
            artifact: artifact,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes)
        let scopes: [CycleFinder.Scope]
        switch arguments.string("scope") ?? "all" {
        case "modules":
            scopes = [.modules]
        case "types":
            scopes = [.types]
        default:
            scopes = [.modules, .types]
        }
        let cycles = scopes.flatMap { finder.cycles(scope: $0) }
        return try Value(cycles.map { CyclePayload(scope: $0.scope.rawValue, members: $0.members) })
    }

    private struct CyclePayload: Codable {
        var scope: String
        var members: [String]
    }
}
