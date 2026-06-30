import ArgumentParser
import Foundation
import UMLDiagram
import UMLLibrary

extension UMLCommand {
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
            try DiagramLimitBounds.validate(maxDepth: maxDepth, maxStates: maxStates)
        }

        mutating func run() throws {
            let artifact = try artifactSource.resolve()

            let diagramFormat = format?.diagramFormat ?? .dot
            let export: DiagramExport
            if let sequenceFrom {
                export = try sequenceExport(artifact: artifact, entryPoint: sequenceFrom)
            } else if let stateFrom {
                export = try stateExport(artifact: artifact, variable: stateFrom)
            } else if package {
                export = packageExport(artifact: artifact)
            } else if callGraph {
                export = try callGraphExport(artifact: artifact)
            } else {
                export = try classExport(artifact: artifact)
            }
            // Single format-dispatch site for every diagram type.
            let rendered = export.render(diagramFormat)
            try rendered.writeOutput(to: output, label: "diagram")
        }

        /// Builds the class-diagram options from flags/config and wraps both renderers.
        private func classExport(artifact: CodeArtifact) throws -> DiagramExport {
            var options = ClassDiagramOptions(language: artifact.standardLanguageConfiguration)

            if let configPath = config {
                let yamlString = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
                try options.applyYAMLConfig(yamlString)
            }

            if let selectedTheme = theme { options.theme = selectedTheme.diagramTheme }
            classFlags.apply(to: &options)

            if let focusConfig = FocusOptionBuilder.make(
                rootTypeName: focus,
                depth: focusDepth,
                direction: focusDirection,
                relationshipKinds: focusRelationship,
                includeInterconnections: !noFocusInterconnections
            ) {
                options.focus = focusConfig
                // A focused view is a local neighbourhood; grouping splits it into mismatched clusters
                // that waste space, so lay it out as a single graph with the root prominent.
                options.groupBy = .none
            }

            // Build the model once; both formats render from it.
            let diagram = artifact.classDiagram(options: options)
            return DiagramExport(
                dot: { ClassDiagramDOTRenderer(options: options).generate(from: diagram) },
                mermaid: { ClassDiagramMermaidRenderer(options: options).generate(from: diagram) }
            )
        }

        /// Traces a sequence diagram from `entryPoint` ("Type.method", or a bare top-level function
        /// name) and wraps both renderers.
        private func sequenceExport(
            artifact: CodeArtifact, entryPoint: String
        ) throws -> DiagramExport {
            let (typeName, methodName) = try parseSequenceEntryPoint(entryPoint)

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
            let selectedTheme = theme?.diagramTheme
            return DiagramExport(
                dot: { SequenceDiagramDOTRenderer(theme: selectedTheme).render(diagram) },
                mermaid: { SequenceDiagramMermaidRenderer(theme: selectedTheme).render(diagram) }
            )
        }

        /// Runs the value-flow state analysis for `variable` and wraps both renderers.
        private func stateExport(
            artifact: CodeArtifact, variable: String
        ) throws -> DiagramExport {
            let configuration = try StateVariableSpec.configuration(from: variable, maxStates: maxStates)
            let diagram: StateDiagram
            do {
                diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
            } catch let error as StateDiagramAnalysisError {
                throw ValidationError(error.message)
            }
            let selectedTheme = theme?.diagramTheme
            return DiagramExport(
                dot: { StateDiagramDOTRenderer(theme: selectedTheme).render(diagram) },
                mermaid: { StateDiagramMermaidRenderer(theme: selectedTheme).render(diagram) }
            )
        }

        /// Builds a package/module dependency diagram and wraps both renderers.
        private func packageExport(artifact: CodeArtifact) -> DiagramExport {
            let diagram = artifact.enriched(configuration: artifact.standardLanguageConfiguration)
                .packageDependencyDiagram()
            let selectedTheme = theme?.diagramTheme
            return DiagramExport(
                dot: { PackageDiagramDOTRenderer(theme: selectedTheme).render(diagram) },
                mermaid: { PackageDiagramMermaidRenderer(theme: selectedTheme).render(diagram) }
            )
        }

        /// Builds a static call graph (optionally scoped) and wraps both renderers.
        private func callGraphExport(artifact: CodeArtifact) throws -> DiagramExport {
            let scope = try parseCallGraphScope()
            let graph = artifact.callGraph(scope: scope, title: callGraphTitle(for: scope))
            // Edges only exist for resolved calls; a node-only graph (callers whose call sites all
            // went unresolved) is not a useful diagram, so treat it as "nothing to draw".
            guard !graph.edges.isEmpty else {
                throw ValidationError(
                    "No resolvable calls found for the requested scope. Call graphs follow "
                    + "explicitly-typed call receivers; try a wider scope or another language."
                )
            }
            // Report resolution coverage on stderr so it doesn't pollute the diagram on stdout.
            let percent = Int((graph.coverage.fraction * 100).rounded())
            let coverageNote = "Call graph: resolved \(graph.coverage.resolved)/\(graph.coverage.total) "
                + "call sites (\(percent)% coverage).\n"
            FileHandle.standardError.write(Data(coverageNote.utf8))
            let selectedTheme = theme?.diagramTheme
            return DiagramExport(
                dot: { CallGraphDOTRenderer(theme: selectedTheme).render(graph) },
                mermaid: { CallGraphMermaidRenderer(theme: selectedTheme).render(graph) }
            )
        }

        /// Parses `--call-graph-scope` (`"type:Name"` / `"module:Name"`) into a `CallGraphScope`.
        private func parseCallGraphScope() throws -> CallGraphScope {
            guard let raw = callGraphScope else { return .wholeCodebase }
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].isEmpty else {
                throw ValidationError("--call-graph-scope must be \"type:Name\" or \"module:Name\".")
            }
            switch parts[0] {
            case "type":
                return .type(parts[1])
            case "module":
                return .module(parts[1])
            default:
                throw ValidationError("--call-graph-scope must start with \"type:\" or \"module:\".")
            }
        }

        private func callGraphTitle(for scope: CallGraphScope) -> String {
            switch scope {
            case .wholeCodebase:
                return "Call graph"
            case .type(let name):
                return "Call graph — \(name)"
            case .module(let name):
                return "Call graph — \(name) module"
            }
        }
    }
}
