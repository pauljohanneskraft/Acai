import Foundation
import MCP
import UMLLibrary
import Yams

/// `uml_check` — validate the codebase against a declarative architecture rules file (forbidden
/// dependencies, cycles, layering, metric budgets, stereotype contracts). Mirrors `uml check --format
/// json`. Read-only: it returns the verdict rather than failing a process.
struct CheckTool: AnalysisTool {
    let name = "uml_check"
    let description = """
        Validate a codebase against a declarative architecture rules file (forbidden dependencies, \
        dependency cycles, layering, metric budgets, stereotype contracts) and return the pass/fail \
        verdict with each violation's file:line — an architecture fitness function.
        """

    var inputSchema: Value {
        objectSchema(
            extraProperties: [
                "rules": [
                    "type": "string",
                    "description": "Path to the YAML architecture rules file."
                ]
            ],
            required: ["path", "rules"])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        // `ConformanceRules` is Codable; decode the YAML rules file directly (the CLI's `.load` helper
        // is a UMLCLI-internal extension, so we mirror it here rather than reach across the target).
        let rulesPath = try arguments.requiredString("rules")
        let ruleSet: ConformanceRules
        do {
            let yaml = try String(contentsOf: URL(fileURLWithPath: rulesPath), encoding: .utf8)
            ruleSet = try YAMLDecoder().decode(ConformanceRules.self, from: yaml)
        } catch {
            // Match every other tool's clean `invalidParams` for bad input rather than surfacing an
            // opaque `internalError` from Foundation/Yams for a missing path or malformed YAML.
            throw MCPError.invalidParams(
                "Could not read architecture rules from \(rulesPath): \(error.localizedDescription)")
        }
        let report = ConformanceEvaluator(
            rules: ruleSet,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)
        return .json(try Value(report))
    }
}
