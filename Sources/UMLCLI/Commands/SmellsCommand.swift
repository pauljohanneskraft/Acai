import ArgumentParser
import UMLConformance
import UMLCore
import UMLLibrary

extension UMLCommand {
    /// Runs the code-smell detectors against curated (or config-supplied) thresholds and reports each
    /// breach as a ranked finding with `file:line` and a fix hint. Unlike `check`, it never fails the
    /// build — it's an exploratory ranking of where to spend refactoring effort.
    struct Smells: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rank code smells (long parameter lists, data classes, low cohesion, …) as findings"
        )

        @OptionGroup var artifactSource: ArtifactSource
        @OptionGroup var selector: SelectorOption

        @Option(name: .long, help: ArgumentHelp(
            "Path to a YAML rules file whose metric budgets are used as the smell thresholds."
            + " Defaults to the built-in curated thresholds when omitted."))
        var rules: String?

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let thresholds = try rules.map { try ConformanceRules.load(contentsOf: $0).budgets }
                ?? SmellScan.defaultThresholds
            let findings = SmellScan(
                artifact: artifact,
                thresholds: thresholds,
                selector: selector.selector,
                annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
            ).findings

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(findings).text
            case .human:
                rendered = humanReport(findings)
            }
            try rendered.writeOutput(to: output, label: "smells")
        }

        private func humanReport(_ findings: [Violation]) -> String {
            guard !findings.isEmpty else { return "No smells found.\n" }
            var lines = findings.map { finding -> String in
                let prefix = finding.source.map { "\($0.filePath):\($0.line): " } ?? ""
                return "\(prefix)\(finding.message)"
            }
            lines.append("")
            lines.append("\(findings.count) smell(s) found.")
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
