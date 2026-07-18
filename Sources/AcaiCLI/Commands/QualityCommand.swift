import ArgumentParser
import Foundation
import AcaiQuality
import AcaiCore
import AcaiDiff
import AcaiLibrary

extension AcaiCommand {
    /// The code-quality gate: validates the relationship graph and metrics against a `quality.yml`
    /// (forbidden dependencies, cycles, layering, metric budgets that subsume the code smells,
    /// stereotype contracts) and fails the build on any violation — a code-quality fitness function.
    /// With `--explore` it never fails and lists dependency cycles too, for exploratory ranking.
    struct Quality: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "quality",
            abstract: "Check the codebase against a declarative code-quality rules file",
            discussion: """
            Validates the relationship graph and metrics against a YAML rules file (forbidden \
            dependencies, dependency cycles, layering, metric budgets, stereotype contracts) and \
            fails the build (non-zero exit) on any violation. Omit --rules to use the built-in \
            curated smell budgets (long parameter lists, data classes, low cohesion, feature envy, …).

              acai quality --source ./ --rules quality.yml
              acai quality --source ./ --explore            # rank smells + list cycles, never fail
              acai quality --source ./ --rules quality.yml --baseline last-release
            """
        )

        enum ScopeOption: String, ExpressibleByArgument, CaseIterable {
            case modules
            case types
            case all
        }

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: ArgumentHelp(
            "Path to the YAML rules file. Defaults to the built-in curated smell budgets when omitted."))
        var rules: String?

        @Flag(name: .long, help: ArgumentHelp(
            "Report findings but always exit 0 (never fail the build), and additionally list"
            + " dependency cycles at --scope — an exploratory ranking of where to spend effort."))
        var explore = false

        @Option(name: .long, help: "Cycle scope listed in --explore mode: modules, types, or all (default).")
        var scope: ScopeOption = .all

        @Option(name: .long, help: ArgumentHelp(
            "Stored analysis name or .json path to compare against; reports architectural drift"
            + " (added/removed edges, metric movement) since that baseline alongside the verdict."
        ))
        var baseline: String?

        @Option(name: .long, help: "Report format: human or json.")
        var format: ReportFormatOption = .human

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let ruleSet = try rules.map { try QualityRules.load(contentsOf: $0) }
                ?? QualityRules.defaultQuality

            let evaluator = QualityEvaluator(
                rules: ruleSet,
                languageResolver: artifact.standardLanguageResolver
            )
            var report = evaluator.evaluate(artifact)
            if explore && ruleSet.cycles == nil {
                report.violations += cycleFindings(artifact)
            }
            let drift = try baseline.map { try driftDiff(current: artifact, baselineRef: $0) }

            try render(report: report, drift: drift).writeOutput(to: output, label: "quality report")

            // The fitness-function verdict: emit the report first, then fail the process so CI stops.
            // `--explore` is an exploratory ranking, so it never fails.
            if !report.isPassing && !explore {
                throw ExitCode.failure
            }
        }

        /// Dependency cycles at the requested scope as `cycle` findings — the exploratory listing that
        /// subsumes the standalone cycles report. Only used in `--explore` mode when the rules file
        /// does not already gate cycles (which the evaluator would report itself).
        private func cycleFindings(_ artifact: CodeArtifact) -> [Violation] {
            let finder = CycleFinder(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
            let scopes: [CycleFinder.Scope] = scope == .all ? [.modules, .types]
                : [scope == .modules ? .modules : .types]
            return scopes.flatMap { cycleScope in
                finder.cycles(scope: cycleScope).map { cycle in
                    Violation(
                        ruleKind: "cycle",
                        message: "\(cycleScope.rawValue) dependency cycle: \(cycle.description).",
                        subject: cycle.members.joined(separator: ","),
                        source: nil,
                        detail: ["scope": cycleScope.rawValue])
                }
            }
        }

        /// Structural drift of the current artifact since a stored baseline. Reuses the diff engine —
        /// no new storage format; a baseline is just a stored `CodeArtifact`.
        private func driftDiff(current: CodeArtifact, baselineRef: String) throws -> ArtifactDiff {
            let base = try ArtifactSource.loadStored(baselineRef)
            return ArtifactDiffer().diff(old: base, new: current)
        }

        private func render(report: QualityReport, drift: ArtifactDiff?) throws -> String {
            switch format {
            case .human:
                var text = report.humanReport()
                if let drift {
                    text += "\n── Drift since baseline ──\n" + drift.humanReport()
                }
                return text
            case .json:
                return try JSONReport(QualityPayload(quality: report, drift: drift)).text
            }
        }
    }
}

/// JSON envelope for `acai quality`: the quality verdict plus optional baseline drift. `drift` is
/// omitted entirely when no `--baseline` was given, keeping the no-baseline JSON minimal.
private struct QualityPayload: Encodable {
    var quality: QualityReport
    var drift: ArtifactDiff?
}
