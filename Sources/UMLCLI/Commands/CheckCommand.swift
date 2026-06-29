import ArgumentParser
import Foundation
import UMLConformance
import UMLCore
import UMLDiff
import UMLLibrary

extension UMLCommand {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check the codebase against a declarative architecture rules file",
            discussion: """
            Validates the relationship graph and metrics against a YAML rules file (forbidden \
            dependencies, dependency cycles, layering, metric budgets, stereotype contracts) and \
            fails the build (non-zero exit) on any violation — an architecture fitness function.

              uml check --source ./ --rules architecture.yml
              uml check --from main-baseline --rules architecture.yml --format json
              uml check --source ./ --rules architecture.yml --baseline last-release
            """
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Path to the YAML rules file.")
        var rules: String

        @Option(name: .long, help: ArgumentHelp(
            "Stored analysis name or .json path to compare against; reports architectural drift"
            + " (added/removed edges, metric movement) since that baseline alongside the verdict."
        ))
        var baseline: String?

        @Option(name: .long, help: "Report format: human or json.")
        var format: ReportFormatOption = .human

        @Flag(name: .long, help: "Report violations but always exit 0 (do not fail the build).")
        var noFail = false

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let ruleSet = try ConformanceRules.load(contentsOf: rules)

            let evaluator = ConformanceEvaluator(
                rules: ruleSet,
                annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
            )
            let report = evaluator.evaluate(artifact)
            let drift = try baseline.map { try driftDiff(current: artifact, baselineRef: $0) }

            try render(report: report, drift: drift).writeOutput(to: output, label: "conformance report")

            // The fitness-function verdict: emit the report first, then fail the process so CI stops.
            if !report.isPassing && !noFail {
                throw ExitCode.failure
            }
        }

        /// Structural drift of the current artifact since a stored baseline. Reuses the diff engine —
        /// no new storage format; a baseline is just a stored `CodeArtifact`.
        private func driftDiff(current: CodeArtifact, baselineRef: String) throws -> ArtifactDiff {
            let base = try ArtifactSource.loadStored(baselineRef)
            return ArtifactDiffer().diff(old: base, new: current)
        }

        private func render(report: ConformanceReport, drift: ArtifactDiff?) throws -> String {
            switch format {
            case .human:
                var text = report.humanReport()
                if let drift {
                    text += "\n── Drift since baseline ──\n" + drift.humanReport()
                }
                return text
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let payload = CheckPayload(conformance: report, drift: drift)
                guard let json = String(data: try encoder.encode(payload), encoding: .utf8) else {
                    throw ValidationError("Failed to encode report as JSON.")
                }
                return json
            }
        }
    }
}

/// JSON envelope for `uml check`: the conformance verdict plus optional baseline drift. `drift` is
/// omitted entirely when no `--baseline` was given, keeping the no-baseline JSON minimal.
private struct CheckPayload: Encodable {
    var conformance: ConformanceReport
    var drift: ArtifactDiff?
}
