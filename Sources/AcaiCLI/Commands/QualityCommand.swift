import ArgumentParser
import Foundation
import AcaiQuality
import AcaiCore
import AcaiDiff
import AcaiLibrary

extension AcaiCommand {
    struct Quality: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "quality",
            abstract: "Check the codebase against a declarative code-quality rules file",
            discussion: """
            Validates the relationship graph and metrics against a YAML rules file (forbidden \
            dependencies, dependency cycles, layering, metric budgets, stereotype contracts, and — \
            with --baseline — expected metric movements) and fails the build (non-zero exit) on any \
            violation. Omit --rules to use the built-in curated smell budgets (long parameter lists, \
            data classes, low cohesion, feature envy, …).

            A rules file's `movements` section states how a metric was expected to move since \
            --baseline (e.g. `{ target: { typeGlob: "Foo" }, metric: fanOut, minImprovement: 2 }` — \
            fanOut must have decreased by at least 2). Omitting minImprovement (or setting it to 0) \
            means "must not get worse". Every other metric on the same target is also checked for a \
            silent regression, so an improvement bought by a hidden cost elsewhere doesn't pass — \
            scope the target selector to what the change actually touched to keep the check focused. \
            Movements are only evaluated when --baseline is given.

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
            guard baseline != nil || ruleSet.movements.isEmpty else {
                throw ValidationError(
                    "The rules file declares \(ruleSet.movements.count) movement rule(s), which require"
                    + " --baseline to evaluate."
                )
            }

            let evaluator = QualityEvaluator(
                rules: ruleSet,
                languageResolver: artifact.standardLanguageResolver
            )
            let baselineArtifact = try baseline.map { try ArtifactSource.loadStored($0) }
            var report = evaluator.evaluate(artifact, baseline: baselineArtifact)
            if explore && ruleSet.cycles == nil {
                report.violations += cycleFindings(artifact)
            }
            let drift = baselineArtifact.map { ArtifactDiffer().diff(old: $0, new: artifact) }

            try render(report: report, drift: drift).writeOutput(to: output, label: "quality report")

            // Emit the report before failing, so CI still shows it. --explore never fails.
            if !report.isPassing && !explore {
                throw ExitCode.failure
            }
        }

        /// Only used in `--explore` mode when the rules file doesn't already gate cycles.
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

/// `drift` is omitted entirely from the JSON when no `--baseline` was given.
private struct QualityPayload: Encodable {
    var quality: QualityReport
    var drift: ArtifactDiff?
}
