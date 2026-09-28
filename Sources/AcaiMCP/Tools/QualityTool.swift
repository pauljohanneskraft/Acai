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
        built-in smell budgets; set 'explore' to rank findings and list cycles without a pass/fail \
        gate; pass 'baseline' to evaluate the rules' expected metric movements and report the drift \
        since that snapshot — how a refactor is proven to have moved the measurements the right way.
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
            ],
            "baseline": [
                "type": "string",
                "description": "Snapshot to compare against — a source directory or a .json artifact,"
                    + " resolved like acai_diff's pathOld. Evaluates the rules' 'movements' and adds the"
                    + " structural drift since it. Required when the rules declare any movement."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let ruleSet = try loadRules(arguments)
        let baseline = try await baselineArtifact(arguments, cache, rules: ruleSet)
        var report = QualityEvaluator(
            rules: ruleSet,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact, baseline: baseline)

        let explore = try arguments.bool("explore") ?? false
        if explore, ruleSet.cycles == nil {
            report.violations += cycleFindings(artifact, scope: arguments.string("scope") ?? "all")
        }
        let payload = Payload(
            quality: report,
            drift: baseline.map { ArtifactDiffer().diff(old: $0, new: artifact) },
            health: HealthCheck(artifact: artifact).summary)
        return .json(try Value(payload))
    }

    /// `drift` is omitted entirely from the JSON when no `baseline` was given, so a caller can tell a
    /// gate run from a drift run by the key's presence — the shape `acai quality --format json` emits.
    private struct Payload: Codable {
        var quality: QualityReport
        var drift: ArtifactDiff?
        var health: HealthCheck.Summary
    }

    /// Mirrors the CLI's refusal to silently skip declared movements: without a baseline there is
    /// nothing to measure them against, so the rules file would pass on a check it never ran.
    private func baselineArtifact(
        _ arguments: ToolArguments, _ cache: AnalysisSnapshotCache, rules: QualityRules
    ) async throws -> CodeArtifact? {
        guard let path = arguments.string("baseline") else {
            guard rules.movements.isEmpty else {
                throw MCPError.invalidParams(
                    "The rules file declares \(rules.movements.count) movement rule(s), which require"
                    + " 'baseline' to evaluate.")
            }
            return nil
        }
        return try await cache.artifact(
            path: path,
            languageNames: arguments.stringArray("languages"),
            refresh: try arguments.bool("refresh") ?? false)
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
