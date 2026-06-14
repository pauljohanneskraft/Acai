import ArgumentParser
import Foundation
import UMLDiagram
import UMLLibrary

extension UMLCommand {
    struct Diagram: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate a diagram (DOT or Mermaid) from an analysis or source directory"
        )

        @Option(name: .long, help: "Name of a stored analysis or path to a .json file.")
        var from: String?

        @Option(name: .long, help: "Path to a source directory to analyze on the fly.")
        var source: String?

        @Option(name: .long, help: ArgumentHelp(
            "Limit analysis to one or more languages" +
            " when using --source. Repeat the flag for" +
            " multiple: --language kotlin --language java."
        ))
        var language: [LanguageOption] = []

        @Option(name: .long, help: "Path to a YAML configuration file.")
        var config: String?

        @Option(name: .long, help: "Output file path for the diagram. Prints to stdout if omitted.")
        var output: String?

        @Option(name: .long, help: "Output format: dot (default), mermaid.")
        var format: FormatOption?

        @Option(name: .long, help: "Graph layout direction: TB, LR, BT, RL.")
        var direction: DirectionOption?

        @Option(name: .long, help: "Color theme: default, dark.")
        var theme: ThemeOption?

        @Option(name: .long, help: "Grouping strategy: file, namespace, none.")
        var groupBy: GroupByOption?

        @Flag(name: .long, help: "Show type members in the diagram.")
        var showMembers: Bool = false

        @Flag(name: .long, help: "Hide type members from the diagram.")
        var noShowMembers: Bool = false

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
            if from == nil && source == nil {
                throw ValidationError("Either --from or --source must be specified.")
            }
            if from != nil && source != nil {
                throw ValidationError("Specify either --from or --source, not both.")
            }
            if showMembers && noShowMembers {
                throw ValidationError("Cannot specify both --show-members and --no-show-members.")
            }
            if sequenceFrom != nil && stateFrom != nil {
                throw ValidationError("Specify either --sequence-from or --state-from, not both.")
            }
            let modeFlags = [sequenceFrom != nil, stateFrom != nil, package].filter { $0 }.count
            if modeFlags > 1 {
                throw ValidationError("Specify only one of --sequence-from, --state-from, or --package.")
            }
        }

        mutating func run() throws {
            let artifact: CodeArtifact
            if let fromValue = from {
                artifact = try loadArtifact(from: fromValue)
            } else if let sourceDir = source {
                let url = URL(fileURLWithPath: sourceDir).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ValidationError("Source directory does not exist: \(sourceDir)")
                }
                let allowedLanguages = language.map { $0.sourceLanguage }
                artifact = try AnalysisService.shared.analyzeProject(at: url, allowedLanguages: allowedLanguages)
                artifact.warnIfParseErrors()
            } else {
                throw ValidationError("Either --from or --source must be specified.")
            }

            let diagramFormat = format?.diagramFormat ?? .dot
            let rendered: String
            if let sequenceFrom {
                rendered = try renderSequence(artifact: artifact, entryPoint: sequenceFrom, format: diagramFormat)
            } else if let stateFrom {
                rendered = try renderState(artifact: artifact, variable: stateFrom, format: diagramFormat)
            } else if package {
                rendered = renderPackage(artifact: artifact, format: diagramFormat)
            } else {
                rendered = try renderClass(artifact: artifact, format: diagramFormat)
            }

            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try rendered.write(to: outputURL, atomically: true, encoding: .utf8)
                print("Wrote diagram to \(outputPath)")
            } else {
                print(rendered)
            }
        }

        /// Builds the class-diagram options from flags/config and renders the artifact.
        private func renderClass(artifact: CodeArtifact, format: DiagramFormat) throws -> String {
            var options = ClassDiagramOptions()

            if let configPath = config {
                let yamlString = try String(contentsOf: URL(fileURLWithPath: configPath), encoding: .utf8)
                try options.applyYAMLConfig(yamlString)
            }

            if let dir = direction { options.layoutDirection = dir.layoutDirection }
            if let selectedTheme = theme { options.theme = selectedTheme.diagramTheme }
            if let selectedGroupBy = groupBy { options.groupBy = selectedGroupBy.groupingStrategy }
            if showMembers { options.showMembers = true }
            if noShowMembers { options.showMembers = false }

            if let focusConfig = FocusOptionBuilder.make(
                rootTypeName: focus,
                depth: focusDepth,
                direction: focusDirection,
                relationshipKinds: focusRelationship,
                includeInterconnections: !noFocusInterconnections
            ) {
                options.focus = focusConfig
            }

            switch format {
            case .dot:
                return DOTGenerator(options: options).generate(from: artifact)
            case .mermaid:
                return ClassDiagramMermaidRenderer(options: options).generate(from: artifact)
            }
        }

        /// Traces a sequence diagram from `entryPoint` ("Type.method") and renders it.
        private func renderSequence(
            artifact: CodeArtifact, entryPoint: String, format: DiagramFormat
        ) throws -> String {
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
            switch format {
            case .dot:
                return SequenceDiagramDOTRenderer(theme: theme?.diagramTheme ?? .default).render(diagram)
            case .mermaid:
                return SequenceDiagramMermaidRenderer().render(diagram)
            }
        }

        /// Runs the value-flow state analysis for `variable` and renders the result.
        private func renderState(
            artifact: CodeArtifact, variable: String, format: DiagramFormat
        ) throws -> String {
            let configuration = try StateVariableSpec.configuration(from: variable, maxStates: maxStates)
            let diagram: StateDiagram
            do {
                diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
            } catch let error as StateDiagramAnalysisError {
                throw ValidationError(error.message)
            }
            switch format {
            case .dot:
                return StateDiagramDOTRenderer(theme: theme?.diagramTheme ?? .default).render(diagram)
            case .mermaid:
                return StateDiagramMermaidRenderer().render(diagram)
            }
        }

        /// Builds a package/module dependency diagram and renders it.
        private func renderPackage(artifact: CodeArtifact, format: DiagramFormat) -> String {
            let diagram = artifact.enriched().packageDependencyDiagram()
            switch format {
            case .dot:
                return PackageDiagramDOTRenderer(theme: theme?.diagramTheme ?? .default).render(diagram)
            case .mermaid:
                return PackageDiagramMermaidRenderer().render(diagram)
            }
        }

        private func loadArtifact(from value: String) throws -> CodeArtifact {
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
