import ArgumentParser
import Foundation
import UMLCore
import UMLLibrary

extension UMLCommand {
    struct Metrics: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute static-analysis metrics (counts, coupling, OO metrics) as JSON"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Output file path for the JSON metrics. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            try artifactSource.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()

            let metrics = artifact.computeMetrics()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metrics)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ValidationError("Failed to encode metrics as JSON.")
            }

            try json.writeOutput(to: output, label: "metrics")
        }
    }
}
