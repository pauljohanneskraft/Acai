import ArgumentParser
import Foundation
import UMLCore
import UMLLibrary

extension UMLCommand {
    struct Metrics: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute static-analysis metrics (counts, coupling, OO metrics) as JSON"
        )

        @Option(name: .long, help: "Name of a stored analysis or path to a .json file.")
        var from: String?

        @Option(name: .long, help: "Path to a source directory to analyze on the fly.")
        var source: String?

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages when using --source." +
            " Repeat the flag for multiple: --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        @Option(name: .long, help: "Output file path for the JSON metrics. Prints to stdout if omitted.")
        var output: String?

        mutating func validate() throws {
            if from == nil && source == nil {
                throw ValidationError("Either --from or --source must be specified.")
            }
            if from != nil && source != nil {
                throw ValidationError("Specify either --from or --source, not both.")
            }
        }

        mutating func run() throws {
            let artifact: CodeArtifact
            if let fromValue = from {
                artifact = try loadArtifact(from: fromValue)
            } else if let sourceDir = source {
                let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ValidationError("Source directory does not exist: \(sourceDir)")
                }
                let allowedLanguages = language.map { $0.sourceLanguage }
                artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: allowedLanguages)
            } else {
                throw ValidationError("Either --from or --source must be specified.")
            }
            artifact.warnIfParseErrors()

            let metrics = artifact.computeMetrics()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metrics)
            guard let json = String(data: data, encoding: .utf8) else {
                throw ValidationError("Failed to encode metrics as JSON.")
            }

            if let outputPath = output {
                try json.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
                print("Wrote metrics to \(outputPath)")
            } else {
                print(json)
            }
        }

        /// Loads a stored artifact: a `.json` file path, or a stored analysis name.
        /// A file produced by `analyze`/`store` is already enriched.
        private func loadArtifact(from value: String) throws -> CodeArtifact {
            let directURL = URL(fileURLWithPath: value)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: directURL))
            }
            let storedURL = UMLConstants.analysisDirectory.appendingPathComponent("\(value).json")
            if FileManager.default.fileExists(atPath: storedURL.path) {
                return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: storedURL))
            }
            throw ValidationError(
                "Could not find analysis '\(value)'. "
                + "Provide a path to a .json file or the name of a stored analysis."
            )
        }
    }
}
