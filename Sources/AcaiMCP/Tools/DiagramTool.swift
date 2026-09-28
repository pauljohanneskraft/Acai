import MCP
import AcaiLibrary

/// `acai_diagram` — one tool over every diagram kind (class/package/sequence/state/callgraph) rendered
/// as DOT or Mermaid text (which the agent can read or embed). Mirrors `acai diagram`. Dispatches to
/// the shared `AcaiDiagram` text exporters, so it stays in lockstep with the CLI.
struct DiagramTool: AnalysisTool {
    let name = "acai_diagram"
    let description = """
        Render a diagram of a codebase as DOT or Mermaid text: a class diagram (optionally focused on \
        one type), a package/module dependency graph, a sequence trace, a value-flow state machine, or \
        a call graph. Use to see structure you can embed in a reply. Pick with 'kind'.
        """

    var inputSchema: Value {
        var properties: [String: Value] = [
            "focus": ["type": "string", "description": "Class diagram: focus on this type's neighbourhood."],
            "focusDepth": ["type": "integer", "description": "Class diagram: max focus traversal depth."],
            "scope": ["type": "string", "description": "Call graph: 'type:Name' or 'module:Name'."],
            "sequenceFrom": ["type": "string", "description": "Sequence: entry point 'Type.method' or a function."],
            "stateFrom": ["type": "string", "description": "State: 'Type.variable' or a global variable."],
            "maxDepth": ["type": "integer", "description": "Sequence: max call-graph depth (default 5)."],
            "maxStates": ["type": "integer", "description": "State: max distinct states (default 20)."],
            "maxNodes": [
                "type": "integer",
                "description": "Class/package: max node count before generation fails (default 2000)."
            ],
            "map": [
                "type": "array", "items": ["type": "string"],
                "description": "Sequence: 'Protocol=Concrete' receiver mappings."
            ]
        ]
        properties.merge(EnumArgument<DiagramKind>.kind.property) { $1 }
        properties.merge(EnumArgument<DiagramFormat>.format.property) { $1 }
        return objectSchema(extraProperties: properties)
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let kind = try EnumArgument<DiagramKind>.kind.value(in: arguments, or: .class)
        let format = try EnumArgument<DiagramFormat>.format.value(in: arguments, or: .mermaid)
        let artifact = try await resolveArtifact(arguments, cache)
        do {
            let export = try export(kind, for: arguments, artifact: artifact)
            var content: [Tool.Content] = []
            if let notice = HealthCheck(artifact: artifact).summary.lowTrustNotice {
                content.append(.text(text: notice, annotations: nil, _meta: nil))
            }
            content.append(.text(text: export.render(format), annotations: nil, _meta: nil))
            return .content(content)
        } catch let error as DiagramRequestError {
            throw MCPError.invalidParams(error.message)
        }
    }

    private func export(
        _ kind: DiagramKind, for arguments: ToolArguments, artifact: CodeArtifact
    ) throws -> DiagramExport {
        let languages = artifact.standardLanguageResolver
        switch kind {
        case .class:
            let options = try classOptions(arguments, languages: languages)
            return try ClassDiagramTextExporter(options: options).export(from: artifact)
        case .package:
            let maxNodes = try arguments.int("maxNodes") ?? DiagramNodeLimit.defaultMaximum
            return try PackageDiagramTextExporter(languages: languages, theme: nil, maxNodes: maxNodes)
                .export(from: artifact)
        case .sequence:
            let request = SequenceDiagramRequest(
                entryPoint: try arguments.requiredString("sequenceFrom"),
                maxDepth: try arguments.int("maxDepth") ?? 5,
                map: try arguments.stringArray("map"))
            return try SequenceDiagramTextExporter(request: request, theme: nil).export(from: artifact)
        case .state:
            let request = StateDiagramRequest(
                variable: try arguments.requiredString("stateFrom"),
                maxStates: try arguments.int("maxStates") ?? 20)
            return try StateDiagramTextExporter(request: request, theme: nil).export(from: artifact)
        case .callgraph:
            let request = CallGraphRequest(scope: CallGraphScopeOption(raw: arguments.string("scope")))
            return try CallGraphTextExporter(request: request, theme: nil).export(from: artifact)
        }
    }

    private func classOptions(
        _ arguments: ToolArguments, languages: LanguageConfigurationResolver
    ) throws -> ClassDiagramOptions {
        var options = ClassDiagramOptions(languages: languages)
        if let focus = arguments.string("focus") {
            options.focus = FocusConfiguration(
                rootTypeName: focus, maxDepth: try arguments.int("focusDepth"), direction: .both)
            // A focused view is a local neighbourhood; grouping splits it into mismatched clusters.
            options.groupBy = .none
        }
        options.maxNodes = try arguments.int("maxNodes") ?? DiagramNodeLimit.defaultMaximum
        return options
    }
}
