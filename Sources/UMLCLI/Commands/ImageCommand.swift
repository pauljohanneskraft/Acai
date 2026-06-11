#if os(macOS)
import ArgumentParser
import CoreGraphics
import Foundation
import UMLDiagram
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

        @Option(name: .long, help: ArgumentHelp(
            "Render a sequence diagram traced from this entry point instead of a class diagram." +
            " Format: \"TypeName.methodName\"."
        ))
        var sequenceFrom: String?

        @Option(name: .long, help: ArgumentHelp(
            "Resolve an interface/protocol to a concrete type when tracing a sequence diagram." +
            " Repeat for multiple: --map Protocol=Concrete --map Other=Impl."
        ))
        var map: [String] = []

        @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
        var maxDepth: Int = 5

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

            let data: Data
            if let sequenceFrom {
                data = try await renderSequence(artifact: artifact, entryPoint: sequenceFrom)
            } else {
                var configuration = DiagramConfiguration()
                configuration.grouping = grouping
                configuration.minimumAccessLevel = minAccess
                if hideMembers {
                    configuration.showProperties = false
                    configuration.showMethods = false
                }
                data = try await MainActor.run {
                    try DiagramImageRenderer.renderPNG(
                        artifact: artifact,
                        configuration: configuration,
                        scale: CGFloat(scale)
                    )
                }
            }

            let outputURL = URL(fileURLWithPath: output)
            try data.write(to: outputURL, options: .atomic)
            print("Wrote image to \(output)")
        }

        /// Traces a sequence diagram from `entryPoint` ("Type.method") and renders it to PNG.
        private func renderSequence(artifact: CodeArtifact, entryPoint: String) async throws -> Data {
            guard let dot = entryPoint.lastIndex(of: ".") else {
                throw ValidationError("--sequence-from must be in the form \"TypeName.methodName\".")
            }
            let typeName = String(entryPoint[..<dot])
            let methodName = String(entryPoint[entryPoint.index(after: dot)...])
            guard !typeName.isEmpty, !methodName.isEmpty else {
                throw ValidationError("--sequence-from must be in the form \"TypeName.methodName\".")
            }

            var typeMapping: [String: String] = [:]
            for entry in map {
                let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw ValidationError("--map must be in the form \"Protocol=Concrete\".")
                }
                typeMapping[parts[0]] = parts[1]
            }

            let diagram = artifact.sequenceDiagram(
                entryPoint: (typeName, methodName),
                maxDepth: maxDepth,
                typeMapping: typeMapping
            )
            guard !diagram.participants.isEmpty else {
                throw ValidationError(
                    "No calls could be traced from \(entryPoint). Sequence diagrams follow "
                    + "explicitly-typed property receivers; try another entry point or --map."
                )
            }
            return try await MainActor.run {
                try DiagramImageRenderer.renderPNG(sequenceDiagram: diagram, scale: CGFloat(scale))
            }
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
