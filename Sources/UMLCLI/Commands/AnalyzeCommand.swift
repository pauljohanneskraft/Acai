import ArgumentParser
import Foundation
import UMLLibrary

extension UMLCommand {
    struct Analyze: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze source code and output the code model as JSON"
        )

        @Argument(help: "Path to the source directory to analyze.")
        var sourceDir: String

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages" +
            " (\(LanguageOption.allValuesList))." +
            " Repeat the flag for multiple:" +
            " --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        @Option(name: .long, help: "Output file path for the JSON result. Prints to stdout if omitted.")
        var output: String?

        mutating func run() throws {
            let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(sourceDir)")
            }

            let allowedLanguages = language.map { $0.sourceLanguage }
            let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: allowedLanguages)
            artifact.warnIfParseErrors()
            let json = try artifact.encodedJSON()

            try json.writeOutput(to: output, label: "analysis")
        }
    }
}
