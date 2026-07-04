import ArgumentParser
import UMLCore
import UMLLibrary

extension UMLCommand {
    /// Reports the blast radius of a type: every type that transitively depends on it, so an agent
    /// can gauge "is this safe to change?" before touching it.
    struct Impact: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the transitive dependents (blast radius) of a type"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Argument(help: "The type to analyze (simple name, qualified name, or id).")
        var type: String

        @Option(name: .long, help: "Limit reverse reachability to this many hops. Unlimited if omitted.")
        var depth: Int?

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()
            let report = ImpactAnalysis(artifact: artifact, rootType: type, maxDepth: depth).report

            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(report).text
            case .human:
                rendered = humanReport(report)
            }
            try rendered.writeOutput(to: output, label: "impact")
        }

        private func humanReport(_ report: ImpactAnalysis.Report) -> String {
            guard report.found else { return "Type '\(report.root)' not found.\n" }
            var lines = ["\(report.root): \(report.blastRadius) transitive dependent(s)."]
            for dependent in report.dependents {
                lines.append("  \(dependent.qualifiedName)\(dependent.location.suffix)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
