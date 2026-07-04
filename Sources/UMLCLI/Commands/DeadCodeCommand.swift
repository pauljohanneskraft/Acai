import ArgumentParser
import UMLDiagram
import UMLLibrary

extension UMLCommand {
    /// Reports dead-code *candidates*: methods no resolved call targets and that aren't reachable by
    /// contract (public API, overrides, protocol requirements, or a language entry-point marker). The
    /// call graph's resolution coverage is reported alongside as the false-positive floor.
    struct DeadCode: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deadcode",
            abstract: "List dead-code candidate methods (uncalled and not an entry point)"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let report = DeadCodeScan(
                artifact: artifact,
                entryPoints: artifact.standardLanguageConfiguration.entryPointMarkers).report

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(report).text
            case .human:
                rendered = humanReport(report)
            }
            try rendered.writeOutput(to: output, label: "dead code")
        }

        private func humanReport(_ report: DeadCodeScan.Report) -> String {
            let coverage = Int((report.coverage.fraction * 100).rounded())
            guard !report.candidates.isEmpty else {
                return "No dead-code candidates (call-graph coverage \(coverage)%).\n"
            }
            var lines = [
                "\(report.candidates.count) dead-code candidate(s) "
                + "— call-graph coverage \(coverage)% (candidates below this floor may be false positives):"
            ]
            for candidate in report.candidates {
                lines.append("  \(candidate.id)\(candidate.location.suffix)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
