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

        /// Class-diagram display flags (direction, grouping, member visibility, inference toggles).
        @OptionGroup var classFlags: ClassDiagramFlags

        @Option(name: .long, help: ArgumentHelp(
            "Render a sequence diagram traced from this entry point instead of a class diagram." +
            " Format: \"TypeName.methodName\", or \"functionName\" for a top-level function."
        ))
        var sequenceFrom: String?

        @Option(name: .long, help: ArgumentHelp(
            "Resolve an interface/protocol to a concrete type when tracing a sequence diagram." +
            " Repeat for multiple: --map Protocol=Concrete --map Other=Impl."
        ))
        var map: [String] = []

        @Option(name: .long, help: "Maximum sequence-diagram call-graph depth.")
        var maxDepth: Int = 5

        @Option(name: .long, help: ArgumentHelp(
            "Render a value-flow state diagram for this variable instead of a class diagram." +
            " Format: \"TypeName.variableName\", or just \"variableName\" for a global."
        ))
        var stateFrom: String?

        @Option(name: .long, help: "Maximum number of distinct states before the analysis fails.")
        var maxStates: Int = 20

        @Flag(name: .long, help: ArgumentHelp(
            "Render a package/module dependency diagram (one node per build module, with"
            + " coupling metrics) instead of a class diagram."
        ))
        var package: Bool = false

        @Flag(name: .long, help: ArgumentHelp(
            "Render a static call graph (one node per method, edges for resolvable calls)"
            + " instead of a class diagram."
        ))
        var callGraph: Bool = false

        @Option(name: .long, help: ArgumentHelp(
            "Scope the call graph to a single type or build module:"
            + " \"type:Name\" or \"module:Name\". Defaults to the whole codebase."
        ))
        var callGraphScope: String?

        @Option(name: .long, help: ArgumentHelp(
            "Focus the class diagram on a single type, showing only the subgraph around it."
            + " Pass the type name."
        ))
        var focus: String?

        @Option(name: .long, help: ArgumentHelp(
            "Maximum focus traversal depth (1 = the type plus its direct neighbours)."
            + " Omit for unlimited."
        ))
        var focusDepth: Int?

        @Option(name: .long, help: "Focus traversal direction: dependencies, dependents, both.")
        var focusDirection: FocusDirectionOption?

        @Option(name: .long, help: ArgumentHelp(
            "Restrict focus to one or more relationship kinds (e.g. inheritance)."
            + " Repeat the flag for multiple. Defaults to all kinds."
        ))
        var focusRelationship: [RelationshipKindOption] = []

        @Flag(name: .long, help: ArgumentHelp(
            "When focusing, draw only the edges actually walked, not every edge among the"
            + " selected types."
        ))
        var noFocusInterconnections: Bool = false

        mutating func validate() throws {
            try artifactSource.validate()
            if classFlags.showMembers && classFlags.noShowMembers {
                throw ValidationError("Cannot specify both --show-members and --no-show-members.")
            }
            if sequenceFrom != nil && stateFrom != nil {
                throw ValidationError("Specify either --sequence-from or --state-from, not both.")
            }
            let modeFlags = [sequenceFrom != nil, stateFrom != nil, package, callGraph].filter { $0 }.count
            if modeFlags > 1 {
                throw ValidationError(
                    "Specify only one of --sequence-from, --state-from, --package, or --call-graph."
                )
            }
            if callGraphScope != nil && !callGraph {
                throw ValidationError("--call-graph-scope requires --call-graph.")
            }
            try DiagramLimits().validate(maxDepth: maxDepth, maxStates: maxStates)
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()

            let diagramFormat = format?.diagramFormat ?? .dot
            let selectedTheme = theme?.diagramTheme
            let export: DiagramExport
            if let sequenceFrom {
                export = try SequenceDiagramTextExporter(
                    request: SequenceDiagramRequest(entryPoint: sequenceFrom, maxDepth: maxDepth, map: map),
                    theme: selectedTheme
                ).export(from: artifact)
            } else if let stateFrom {
                export = try StateDiagramTextExporter(
                    request: StateDiagramRequest(variable: stateFrom, maxStates: maxStates),
                    theme: selectedTheme
                ).export(from: artifact)
            } else if package {
                export = PackageDiagramTextExporter(
                    languages: artifact.standardLanguageResolver, theme: selectedTheme
                ).export(from: artifact)
            } else if callGraph {
                let scopeOption = CallGraphScopeOption(raw: callGraphScope)
                export = try CallGraphTextExporter(
                    request: CallGraphRequest(scope: scopeOption, title: try scopeOption.title()),
                    theme: selectedTheme
                ).export(from: artifact)
            } else {
                let exporter = ClassDiagramTextExporter(options: try classDiagramOptions(for: artifact))
                export = exporter.export(from: artifact)
            }
            // Single format-dispatch site for every diagram type.
            let rendered = export.render(diagramFormat)
            try rendered.writeOutput(to: output, label: "diagram")
        }

        /// Builds the class-diagram options from the flags/config/theme/focus inputs.
        private func classDiagramOptions(for artifact: CodeArtifact) throws -> ClassDiagramOptions {
            var options = ClassDiagramOptions(languages: artifact.standardLanguageResolver)

            if let configPath = config {
                let yamlString = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
                try options.applyYAMLConfig(yamlString)
            }

            if let selectedTheme = theme { options.theme = selectedTheme.diagramTheme }
            classFlags.apply(to: &options)

            if let focusConfig = FocusOptionBuilder(
                rootTypeName: focus,
                depth: focusDepth,
                direction: focusDirection,
                relationshipKinds: focusRelationship,
                includeInterconnections: !noFocusInterconnections
            ).configuration {
                options.focus = focusConfig
                // A focused view is a local neighbourhood; grouping splits it into mismatched clusters
                // that waste space, so lay it out as a single graph with the root prominent.
                options.groupBy = .none
            }
            return options
        }
    }
}
