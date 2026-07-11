import Foundation
import MCP
import UMLLibrary
import Yams

/// `uml_quality` — validate the codebase against a declarative code-quality rules file (forbidden
/// dependencies, cycles, layering, metric budgets that subsume the code smells, stereotype contracts)
/// and return the pass/fail verdict with each violation's file:line. Mirrors `uml quality --format
/// json`. Omit `rules` for the built-in curated smell budgets; set `explore` for a non-failing ranking
/// that also lists dependency cycles. Read-only: it returns the verdict rather than failing a process.
struct QualityTool: AnalysisTool {
    let name = "uml_quality"
    let description = """
        Check code quality against a declarative rules file: forbidden dependencies, dependency \
        cycles, layering, metric budgets, stereotype contracts, and the curated code smells (long \
        parameter lists, data classes, low cohesion, feature envy, god classes). Returns each \
        violation's file:line and a fix hint — a code-quality fitness function. Omit 'rules' for the \
        built-in smell budgets; set 'explore' to rank findings and list cycles without a pass/fail gate.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "rules": [
                "type": "string",
                "description": "Path to the YAML rules file. Omit for the built-in curated smell budgets."
            ],
            "explore": [
                "type": "boolean",
                "description": "Rank findings and additionally list dependency cycles at 'scope' (no gate)."
            ],
            "scope": [
                "type": "string",
                "enum": ["modules", "types", "all"],
                "description": "Cycle scope listed in explore mode: modules, types, or all (default)."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let ruleSet = try loadRules(arguments)
        var report = QualityEvaluator(
            rules: ruleSet,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)

        let explore = try arguments.bool("explore") ?? false
        if explore, ruleSet.cycles == nil {
            report.violations += cycleFindings(artifact, scope: arguments.string("scope") ?? "all")
        }
        return .json(try Value(report))
    }

    /// The rules file at `rules`, or the built-in curated smell budgets when omitted. Decodes the YAML
    /// directly (the CLI's `.load` helper is UMLCLI-internal), mapping read/parse failure onto
    /// `invalidParams` rather than an opaque `internalError`.
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

    /// Dependency cycles at the requested scope as `cycle` findings — the exploratory listing that
    /// subsumes uml_cycles, used only in explore mode when the rules don't already gate cycles.
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
