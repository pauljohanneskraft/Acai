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
        @OptionGroup var generatedScope: GeneratedScopeOption

        @Option(name: .long, help: "Report format: json (default) or human.")
        var format: ReportFormatOption = .json

        @Option(name: .long, help: ArgumentHelp(
            "Per-type ranking for the human tables: "
            + "fanOut (default), fanIn, weightedMethods, depthOfInheritance, numberOfChildren, "
            + "responseForClass, publicMemberCount, publicMemberRatio, mutablePublicState, maxParameters, "
            + "meanParameters, dataClassScore, overrideCount, nestingDepth, deepAndWide, lackOfCohesion, "
            + "featureEnvyMethods."))
        var sort: MetricsSortKey = .fanOut

        @Option(name: .long, help: "Limit the human type table to the top N rows.")
        var top: Int?

        @Option(name: .long, help: "Output file path. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let metrics = try generatedScope.applied(to: artifactSource.resolve()).computeMetrics()
            let rendered: String
            switch format {
            case .json:
                rendered = try JSONReport(metrics).text
            case .human:
                rendered = MetricsTextReport(metrics: metrics, sort: sort, top: top).render() + "\n"
            }
            try rendered.writeOutput(to: output, label: "metrics")
        }
    }
}
