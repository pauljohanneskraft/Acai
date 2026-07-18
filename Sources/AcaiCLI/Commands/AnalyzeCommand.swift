import ArgumentParser
import Foundation
import AcaiCore
import AcaiLibrary

extension AcaiCommand {
    struct Analyze: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze source code and output the code model as JSON, or its parse health"
        )

        @Option(name: .long, help: "Name of a stored analysis or path to a .json file.")
        var from: String?

        @Option(name: .long, help: "Path to a source directory to analyze on the fly.")
        var source: String?

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages when using --source/a path" +
            " (\(LanguageOption.allValuesList))." +
            " Repeat the flag for multiple: --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        @Flag(name: .long, help: ArgumentHelp(
            "Report parse health (a trust score over parse diagnostics) instead of the code model."
            + " A low score means an audit built on this artifact is untrustworthy — run it first."))
        var health = false

        @Option(name: .long, help: "Health-report format when --health is set: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path for the result. Prints to stdout if omitted.")
        var output: String?

        @OptionGroup var generatedScope: GeneratedScopeOption

        mutating func run() throws {
            if from == nil && source == nil {
                throw ValidationError("Either --from or --source must be specified.")
            }
            if from != nil && source != nil {
                throw ValidationError("Specify either --from or --source, not both.")
            }
            let artifact = try generatedScope.applied(
                to: ArtifactSource.resolve(from: from, source: source, language: language))
            if health {
                try healthReport(artifact).writeOutput(to: output, label: "health report")
            } else {
                try JSONReport(artifact).text.writeOutput(to: output, label: "analysis")
            }
        }

        private func healthReport(_ artifact: CodeArtifact) throws -> String {
            let report = HealthCheck(artifact: artifact).report
            switch format {
            case .json:
                return try JSONReport(report).text
            case .human:
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
}
