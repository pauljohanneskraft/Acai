#if os(macOS)
import ArgumentParser
import CoreGraphics
import Foundation
import SwiftUI
import AcaiDiagram
import AcaiDiff
import AcaiLibrary
import AcaiRender

extension AcaiCommand {
    /// macOS-only: rendering needs SwiftUI's `ImageRenderer`, which requires a GUI / window-server session.
    struct Image: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "Render a class diagram to a PNG image (macOS only)"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Output PNG file path.")
        var output: String

        @Option(name: .long, help: "Old side for a delta image: a source directory to analyze.")
        var sourceOld: String?

        @Option(name: .long, help: "Old side for a delta image: a stored analysis name or .json path.")
        var fromOld: String?

        @Option(name: .long, help: "Grouping strategy: none, directory, product.")
        var grouping: ClassDiagramConfiguration.Grouping = .product

        @Option(name: .long, help: ArgumentHelp(
            "Only show members (and whole types) at or above this access level:" +
            " open, public, packagePrivate, internal, protected, filePrivate, private."
        ))
        var minAccess: AccessLevel?

        @Flag(name: .long, help: "Hide type members (properties and methods).")
        var hideMembers: Bool = false

        @Option(name: .long, help: "Output resolution scale factor.")
        var scale: Double = 2

        @Option(name: .long, help: "Colour theme for the rendered image: default (light) or dark.")
        var theme: ThemeOption = .default

        private var palette: DiagramPalette {
            theme == .dark ? .dark : .light
        }

        @OptionGroup var shape: DiagramShapeFlags

        mutating func validate() throws {
            try artifactSource.validate()
            try shape.validate()
        }

        private func resolveOldArtifact() throws -> CodeArtifact? {
            guard fromOld != nil || sourceOld != nil else { return nil }
            return try ArtifactSource.resolve(from: fromOld, source: sourceOld, language: artifactSource.language)
        }

        mutating func run() async throws {
            let artifact = try artifactSource.resolve()
            let oldArtifact = try resolveOldArtifact()

            let data = try await renderData(artifact: artifact, old: oldArtifact)

            let outputURL = URL(fileURLWithPath: output)
            try data.write(to: outputURL, options: .atomic)
            print("Wrote image to \(output)")
        }

        private func renderData(artifact: CodeArtifact, old: CodeArtifact?) async throws -> Data {
            if let sequenceFrom = shape.sequenceFrom {
                let exporter = SequenceImageExporter(
                    scale: scale, palette: palette, entryPoint: sequenceFrom,
                    maxDepth: shape.maxDepth, map: shape.map)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if let stateFrom = shape.stateFrom {
                let exporter = StateImageExporter(
                    scale: scale, palette: palette, variable: stateFrom, maxStates: shape.maxStates)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if shape.package {
                let exporter = PackageImageExporter(
                    scale: scale, palette: palette, languages: artifact.standardLanguageResolver)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else if shape.callGraph {
                let exporter = CallGraphImageExporter(
                    scale: scale, palette: palette, scope: shape.callGraphScopeOption)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            } else {
                let exporter = ClassImageExporter(
                    scale: scale, palette: palette, configuration: classDiagramConfiguration(),
                    languages: artifact.standardLanguageResolver)
                if let old { return try await exporter.renderDelta(old: old, new: artifact) }
                return try await exporter.render(artifact: artifact)
            }
        }

        private func classDiagramConfiguration() -> ClassDiagramConfiguration {
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = grouping
            configuration.minimumAccessLevel = minAccess
            if hideMembers {
                configuration.showProperties = false
                configuration.showMethods = false
            }
            configuration.focus = shape.focusConfiguration
            // A focused view is a local neighbourhood around one type; module/directory boxing would
            // split it into mismatched clusters, so lay it out as a single graph instead.
            if configuration.focus != nil {
                configuration.grouping = .none
            }
            return configuration
        }
    }
}

extension ClassDiagramConfiguration.Grouping: ExpressibleByArgument {}
#endif
