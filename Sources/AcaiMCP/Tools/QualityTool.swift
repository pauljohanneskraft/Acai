import Foundation
import MCP
import AcaiLibrary

/// `acai_quality` — validates the codebase against a declarative code-quality rules file and returns
/// the pass/fail verdict with each violation's file:line. Mirrors `acai quality --format json`.
struct QualityTool: AnalysisTool {
    let name = "acai_quality"
    let description = """
        Check code quality against a declarative rules file: forbidden dependencies, dependency \
        cycles, layering, metric budgets, stereotype contracts, and the curated code smells (long \
        parameter lists, data classes, low cohesion, feature envy, god classes). Returns each \
        violation's file:line and a fix hint — a code-quality fitness function. Omit 'rules' for the \
        built-in smell budgets; set 'explore' to rank findings and list cycles without a pass/fail gate.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: rulesProperty.merging([
            "explore": [
                "type": "boolean",
                "description": "Rank findings and additionally list dependency cycles at 'scope' (no gate)."
            ],
            "scope": [
                "type": "string",
                "enum": ["modules", "types", "all"],
                "description": "Cycle scope listed in explore mode: modules, types, or all (default)."
            ]
        ]) { _, new in new })
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let ruleSet = try qualityRules(arguments)
        var report = QualityEvaluator(
            rules: ruleSet,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)

        let explore = try arguments.bool("explore") ?? false
        if explore, ruleSet.cycles == nil {
            report.violations += cycleFindings(artifact, scope: arguments.string("scope") ?? "all")
        }
        let payload = Payload(quality: report, health: HealthCheck(artifact: artifact).summary)
        return .json(try Value(payload))
    }

    private struct Payload: Codable {
        var quality: QualityReport
        var health: HealthCheck.Summary
    }

    private func cycleFindings(_ artifact: CodeArtifact, scope: String) -> [Violation] {
        let finder = CycleFinder(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
        let scopes: [CycleFinder.Scope] = scope == "types" ? [.types]
            : scope == "modules" ? [.modules] : [.modules, .types]
        return scopes.flatMap { cycleScope in
            finder.cycles(scope: cycleScope).map { cycle in
                Violation(
                    ruleKind: "cycle",
                    message: "\(cycleScope.rawValue) dependency cycle: \(cycle.description).",
                    subject: cycle.members.joined(separator: ","),
                    detail: ["scope": cycleScope.rawValue])
            }
        }
    }
}
