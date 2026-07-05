import MCP
import UMLLibrary

/// `uml_enums` — every enum-like type with its cases, raw values and associated-value shapes, each
/// with `file:line`. Mirrors `uml enums --format json`.
struct EnumsTool: AnalysisTool {
    let name = "uml_enums"
    let description = """
        Inventory every enum-like type with its cases, raw values, and associated-value shapes, each \
        with a file:line jump target. Use to review or reason about a codebase's enumerations.
        """

    var inputSchema: Value { objectSchema() }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let entries = EnumInventory(artifact: try await resolveArtifact(arguments, cache)).entries
        return .json(try Value(entries))
    }
}
