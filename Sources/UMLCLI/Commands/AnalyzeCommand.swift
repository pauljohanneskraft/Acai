import ArgumentParser
import Foundation
import UMLLibrary

extension UMLCommand {
    struct Analyze: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze source code and output the code model as JSON"
        )

        @Argument(help: "(Deprecated) source directory to analyze; prefer --source.")
        var sourceDir: String?

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

        @Option(name: .long, help: "Output file path for the JSON result. Prints to stdout if omitted.")
        var output: String?

        mutating func run() throws {
            // Unifies on the shared `ArtifactSource` resolution; a bare positional path is a
            // deprecated alias for `--source`. (Done here, not in `validate()`, so the auto-invoked
            // group validate can't pre-empt the alias.)
            let effectiveSource = source ?? sourceDir
            if from == nil && effectiveSource == nil {
                throw ValidationError("Either --from or --source (or a positional path) must be specified.")
            }
            if from != nil && effectiveSource != nil {
                throw ValidationError("Specify either --from or --source, not both.")
            }
            let artifact = try ArtifactSource.resolve(from: from, source: effectiveSource, language: language)
            try JSONReport(artifact).text.writeOutput(to: output, label: "analysis")
        }
    }
}
