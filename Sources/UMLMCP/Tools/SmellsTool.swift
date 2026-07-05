import MCP
import UMLLibrary

/// `uml_smells` — ranked code-smell findings (long parameter lists, data classes, low cohesion, …)
/// against curated thresholds, each with `file:line` and a fix hint. Mirrors `uml smells`.
struct SmellsTool: AnalysisTool {
    let name = "uml_smells"
    let description = """
        Rank code smells — long parameter lists, data classes, deep nesting, low cohesion, feature \
        envy — as findings with file:line and a fix hint, worst first. Use to decide where refactoring \
        effort pays off. Narrow with the selector facets (module, type, kind, …).
        """

    var inputSchema: Value { objectSchema(extraProperties: selectorProperties) }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let findings = SmellScan(
            artifact: artifact,
            selector: selector(from: arguments),
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
        ).findings
        return .json(try Value(findings))
    }
}
