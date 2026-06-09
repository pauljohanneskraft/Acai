#if os(macOS)
import ArgumentParser
import CoreGraphics
import Foundation
import UMLLibrary
import UMLRender

extension UMLCommand {
    /// Renders a class diagram to a PNG image using the same SwiftUI views and layout engine
    /// as the macOS app (via `UMLRender`), rather than going through DOT/Graphviz.
    ///
    /// macOS-only: image rendering relies on SwiftUI's `ImageRenderer`, which needs a GUI /
    /// window-server session. On other platforms this subcommand is not registered.
    struct Image: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Render a class diagram to a PNG image (macOS only)"
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

        @Option(name: .long, help: "Output PNG file path.")
        var output: String

        @Option(name: .long, help: "Grouping strategy: none, directory, product.")
        var grouping: DiagramConfiguration.Grouping = .product

        @Option(name: .long, help: ArgumentHelp(
            "Only show members (and whole types) at or above this access level:" +
            " open, public, packagePrivate, internal, protected, filePrivate, private."
        ))
        var minAccess: AccessLevel?

        @Flag(name: .long, help: "Hide type members (properties and methods).")
        var hideMembers: Bool = false

        @Option(name: .long, help: "Output resolution scale factor.")
        var scale: Double = 2

        mutating func validate() throws {
            if from == nil && source == nil {
                throw ValidationError("Either --from or --source must be specified.")
            }
            if from != nil && source != nil {
                throw ValidationError("Specify either --from or --source, not both.")
            }
        }

        mutating func run() async throws {
            let artifact = try loadArtifact()

            var configuration = DiagramConfiguration()
            configuration.grouping = grouping
            configuration.minimumAccessLevel = minAccess
            if hideMembers {
                configuration.showProperties = false
                configuration.showMethods = false
            }

            let data = try await MainActor.run {
                try DiagramImageRenderer.renderPNG(
                    artifact: artifact,
                    configuration: configuration,
                    scale: CGFloat(scale)
                )
            }

            let outputURL = URL(fileURLWithPath: output)
            try data.write(to: outputURL, options: .atomic)
            print("Wrote image to \(output)")
        }

        private func loadArtifact() throws -> CodeArtifact {
            if let fromValue = from {
                return try Self.loadStoredArtifact(from: fromValue)
            }
            guard let sourceDir = source else {
                throw ValidationError("Either --from or --source must be specified.")
            }
            let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Source directory does not exist: \(sourceDir)")
            }
            let allowedLanguages = language.map { $0.sourceLanguage }
            return try AnalysisService.shared.analyzeProject(at: url, allowedLanguages: allowedLanguages)
        }

        private static func loadStoredArtifact(from value: String) throws -> CodeArtifact {
            let directURL = URL(fileURLWithPath: value)
            if FileManager.default.fileExists(atPath: directURL.path) {
                let data = try Data(contentsOf: directURL)
                return try JSONDecoder().decode(CodeArtifact.self, from: data)
            }

            let storedURL = UMLConstants.analysisDirectory.appendingPathComponent("\(value).json")
            if FileManager.default.fileExists(atPath: storedURL.path) {
                let data = try Data(contentsOf: storedURL)
                return try JSONDecoder().decode(CodeArtifact.self, from: data)
            }

            throw ValidationError(
                "Could not find analysis '\(value)'. "
                + "Provide a path to a .json file or the name of a stored analysis."
            )
        }
    }
}

extension DiagramConfiguration.Grouping: ExpressibleByArgument {}
extension AccessLevel: ExpressibleByArgument {}
#endif
