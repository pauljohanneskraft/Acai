import ArgumentParser
import Foundation
import AcaiDiagram
import AcaiLibrary

extension AcaiCommand {
    struct Diagram: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate a diagram (DOT or Mermaid) from an analysis or source directory"
        )

        @OptionGroup var artifactSource: ArtifactSource

        @Option(name: .long, help: "Path to a YAML configuration file.")
        var config: String?

        @Option(name: .long, help: "Output file path for the diagram. Prints to stdout if omitted.")
        var output: String?

        @Option(name: .long, help: "Output format: dot (default), mermaid.")
        var format: FormatOption?

        @Option(name: .long, help: "Color theme: default, dark.")
        var theme: ThemeOption?

        @OptionGroup var classFlags: ClassDiagramFlags

        @OptionGroup var shape: DiagramShapeFlags

        mutating func validate() throws {
            try artifactSource.validate()
            if classFlags.showMembers && classFlags.noShowMembers {
                throw ValidationError("Cannot specify both --show-members and --no-show-members.")
            }
            try shape.validate()
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()

            let diagramFormat = format?.diagramFormat ?? .dot
            let selectedTheme = theme?.diagramTheme
            let export: DiagramExport
            if let sequenceFrom = shape.sequenceFrom {
                export = try SequenceDiagramTextExporter(
                    request: SequenceDiagramRequest(
                        entryPoint: sequenceFrom, maxDepth: shape.maxDepth, map: shape.map
                    ),
                    theme: selectedTheme
                ).export(from: artifact)
            } else if let stateFrom = shape.stateFrom {
                export = try StateDiagramTextExporter(
                    request: StateDiagramRequest(variable: stateFrom, maxStates: shape.maxStates),
                    theme: selectedTheme
                ).export(from: artifact)
            } else if shape.package {
                export = PackageDiagramTextExporter(
                    languages: artifact.standardLanguageResolver, theme: selectedTheme
                ).export(from: artifact)
            } else if shape.callGraph {
                let scopeOption = shape.callGraphScopeOption
                export = try CallGraphTextExporter(
                    request: CallGraphRequest(scope: scopeOption, title: try scopeOption.title()),
                    theme: selectedTheme
                ).export(from: artifact)
            } else {
                let exporter = ClassDiagramTextExporter(options: try classDiagramOptions(for: artifact))
                export = exporter.export(from: artifact)
            }
            let rendered = export.render(diagramFormat)
            try rendered.writeOutput(to: output, label: "diagram")
        }

        private func classDiagramOptions(for artifact: CodeArtifact) throws -> ClassDiagramOptions {
            var options = ClassDiagramOptions(languages: artifact.standardLanguageResolver)

            if let configPath = config {
                let yamlString = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
                try options.applyYAMLConfig(yamlString)
            }

            if let selectedTheme = theme { options.theme = selectedTheme.diagramTheme }
            classFlags.apply(to: &options)

            if let focusConfig = shape.focusConfiguration {
                options.focus = focusConfig
                // A focused view is a local neighbourhood; grouping would split it into mismatched
                // clusters, so lay it out as a single graph.
                options.groupBy = .none
            }
            return options
        }
    }
}
