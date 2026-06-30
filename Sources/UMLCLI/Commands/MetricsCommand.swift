import ArgumentParser
import Foundation
import UMLCore
import UMLLibrary

extension MetricsSortKey: ExpressibleByArgument {}

extension UMLCommand {
    struct Metrics: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute static-analysis metrics (counts, coupling, OO metrics) as JSON"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: ArgumentHelp(
            "Per-type ranking for the human table: "
            + "fanOut (default), fanIn, weightedMethods, depthOfInheritance, numberOfChildren."))
        var sort: MetricsSortKey = .fanOut

        @Option(name: .long, help: "Limit the human type table to the top N rows.")
        var top: Int?

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let metrics = try artifactSource.resolve().computeMetrics()
            let rendered: String
            switch format {
            case .json:
                rendered = try encodeJSON(metrics)
            case .human:
                rendered = MetricsTextReport(metrics: metrics, sort: sort, top: top).render() + "\n"
            }
            try rendered.writeOutput(to: output, label: "metrics")
        }

        private func encodeJSON(_ metrics: CodeMetrics) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metrics)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ValidationError("Failed to encode metrics as JSON.")
            }
            return json
        }
    }
}
