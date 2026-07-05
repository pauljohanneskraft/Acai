import MCP
import UMLLibrary

/// `uml_callcycles` — method-level call cycles (mutual recursion / tangled method clusters): the
/// strongly-connected components of the call graph. Mirrors `uml call-cycles --format json`.
struct CallCyclesTool: AnalysisTool {
    let name = "uml_callcycles"
    let description = """
        Detect method-level call cycles (mutual recursion / tangled method clusters) — the \
        strongly-connected components of the call graph, each member with file:line. Complements \
        uml_cycles (type/module) and uml_callgraph. Optionally scope with 'type:Name' or 'module:Name'.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "scope": [
                "type": "string",
                "description": "Scope: 'type:Name' or 'module:Name'. Whole codebase if omitted."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let scope = try resolvedCallGraphScope(arguments.string("scope"))
        return .json(try Value(MethodCycles(artifact: artifact, scope: scope).clusters))
    }
}
