import Foundation
import MCP
import AcaiLibrary
import Yams

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
        var properties: [String: Value] = [
            "rules": [
                "type": "string",
                "description": "Path to the YAML rules file. Omit for the built-in curated smell budgets."
            ],
            "explore": [
                "type": "boolean",
                "description": "Rank findings and additionally list dependency cycles at 'scope' (no gate)."
            ]
        ]
        properties.merge(EnumArgument<CycleScope>.scope.property) { $1 }
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let scope = try EnumArgument<CycleScope>.scope.value(in: arguments, or: .all)
        let artifact = try await resolveArtifact(arguments, cache)
        let ruleSet = try loadRules(arguments)
        var report = QualityEvaluator(
            rules: ruleSet,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)

        let explore = try arguments.bool("explore") ?? false
        if explore, ruleSet.cycles == nil {
            report.violations += cycleFindings(artifact, scope: scope)
        }
        let payload = Payload(quality: report, health: HealthCheck(artifact: artifact).summary)
        return .json(try Value(payload))
    }

    private struct Payload: Codable {
        var quality: QualityReport
        var health: HealthCheck.Summary
    }

    /// Decodes the YAML directly since the CLI's `.load` helper is AcaiCLI-internal.
    private func loadRules(_ arguments: ToolArguments) throws -> QualityRules {
        guard let rulesPath = arguments.string("rules") else { return .defaultQuality }
        do {
            let yaml = try String(contentsOf: URL(fileURLWithPath: rulesPath), encoding: .utf8)
            return try YAMLDecoder().decode(QualityRules.self, from: yaml)
        } catch {
            throw MCPError.invalidParams(
                "Could not read quality rules from \(rulesPath): \(error.localizedDescription)")
        }
    }

    private func cycleFindings(_ artifact: CodeArtifact, scope: CycleScope) -> [Violation] {
        let finder = CycleFinder(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
        return scope.finderScopes.flatMap { cycleScope in
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
