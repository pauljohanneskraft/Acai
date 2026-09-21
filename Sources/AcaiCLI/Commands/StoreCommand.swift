import ArgumentParser
import Foundation
import AcaiLibrary

extension AcaiCommand {
    struct Store: AsyncParsableCommand {
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

        mutating func run() async throws {
            let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(sourceDir)")
            }
            let resolvedPath = url.resolvingSymlinksInPath().path

            let allowedLanguages = language.map { $0.sourceLanguage }
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: url, allowedLanguages: allowedLanguages)
            artifact.warnIfParseErrors()

            let fingerprint = SourceTreeFingerprint(directory: url).compute()
            let filePath = try AnalysisStore.standard.write(
                artifact, sourcePath: resolvedPath, fingerprint: fingerprint, named: name)
            print("Stored analysis '\(name)' at \(filePath.path)")
        }
    }
}
