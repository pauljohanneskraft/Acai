import ArgumentParser
import UMLCore
import UMLLibrary

extension UMLCommand {
    /// Reports parse health: how much of the codebase parsed cleanly, and where it didn't. A low
    /// score means the rest of an audit built on this artifact is untrustworthy — run it first.
    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report parse health (a trust score over parse diagnostics)"
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
            let report = HealthCheck(artifact: try artifactSource.resolve()).report
            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(report).text
            case .human:
                rendered = humanReport(report)
            }
            try rendered.writeOutput(to: output, label: "health report")
        }

        private func humanReport(_ report: HealthCheck.Report) -> String {
            let percent = Int((report.score * 100).rounded())
            var lines = [
                "Parse health: \(percent)% "
                + "(\(report.diagnosticCount) diagnostic(s) across \(report.typeCount) type(s))"
            ]
            for diagnostic in report.diagnostics {
                lines.append(
                    "  \(diagnostic.location.jumpTarget): \(diagnostic.kind.rawValue): \(diagnostic.message)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
