import ArgumentParser
import Foundation
import AcaiLibrary

extension AcaiCommand {
    struct Store: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze source code and store the result under a given name"
        )

        @Argument(help: "Name for the stored analysis.")
        var name: String

        @Argument(help: "Path to the source directory to analyze.")
        var sourceDir: String

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages" +
            " (\(LanguageOption.allValuesList))." +
            " Repeat the flag for multiple:" +
            " --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        mutating func run() throws {
            let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(sourceDir)")
            }

            let allowedLanguages = language.map { $0.sourceLanguage }
            let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: allowedLanguages)
            artifact.warnIfParseErrors()
            let json = try JSONReport(artifact).text

            let storageDir = AcaiConstants.standard.analysisDirectory
            try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

            let filePath = storageDir.appendingPathComponent("\(name).json")
            try json.write(to: filePath, atomically: true, encoding: .utf8)
            print("Stored analysis '\(name)' at \(filePath.path)")
        }
    }
}
