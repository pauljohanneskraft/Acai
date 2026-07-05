import MCP
import UMLLibrary

/// `uml_diagram` — one tool over every diagram kind (class/package/sequence/state/callgraph) rendered
/// as DOT or Mermaid text (which the agent can read or embed). Mirrors `uml diagram`. Dispatches to
/// the shared `UMLDiagram` text exporters, so it stays in lockstep with the CLI.
struct DiagramTool: AnalysisTool {
    let name = "uml_diagram"
    let description = """
        Render a diagram of a codebase as DOT or Mermaid text: a class diagram (optionally focused on \
        one type), a package/module dependency graph, a sequence trace, a value-flow state machine, or \
        a call graph. Use to see structure you can embed in a reply. Pick with 'kind'.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "kind": [
                "type": "string",
                "enum": ["class", "package", "sequence", "state", "callgraph"],
                "description": "Diagram kind (default class)."
            ],
            "format": [
                "type": "string",
                "enum": ["dot", "mermaid"],
                "description": "Output format (default mermaid)."
            ],
            "focus": ["type": "string", "description": "Class diagram: focus on this type's neighbourhood."],
            "focusDepth": ["type": "integer", "description": "Class diagram: max focus traversal depth."],
            "scope": ["type": "string", "description": "Call graph: 'type:Name' or 'module:Name'."],
            "sequenceFrom": ["type": "string", "description": "Sequence: entry point 'Type.method' or a function."],
            "stateFrom": ["type": "string", "description": "State: 'Type.variable' or a global variable."],
            "maxDepth": ["type": "integer", "description": "Sequence: max call-graph depth (default 5)."],
            "maxStates": ["type": "integer", "description": "State: max distinct states (default 20)."],
            "map": [
                "type": "array", "items": ["type": "string"],
                "description": "Sequence: 'Protocol=Concrete' receiver mappings."
            ]
        ])
    }

    func run(arguments: ToolArguments, cache: AnalysisSnapshotCache) async throws -> ToolOutput {
        let artifact = try await resolveArtifact(arguments, cache)
        let format = try diagramFormat(arguments.string("format"))
        do {
            let export = try export(for: arguments, artifact: artifact)
            return .content([.text(text: export.render(format), annotations: nil, _meta: nil)])
        } catch let error as DiagramRequestError {
            throw MCPError.invalidParams(error.message)
        }
    }

    private func diagramFormat(_ raw: String?) throws -> DiagramFormat {
        switch raw ?? "mermaid" {
        case "dot":
            return .dot
        case "mermaid":
            return .mermaid
        default:
            throw MCPError.invalidParams("format must be 'dot' or 'mermaid'.")
        }
    }

    private func export(for arguments: ToolArguments, artifact: CodeArtifact) throws -> DiagramExport {
        let language = artifact.standardLanguageConfiguration
        switch arguments.string("kind") ?? "class" {
        case "class":
            return ClassDiagramTextExporter(options: classOptions(arguments, language: language)).export(from: artifact)
        case "package":
            return PackageDiagramTextExporter(language: language, theme: nil).export(from: artifact)
        case "sequence":
            let request = SequenceDiagramRequest(
                entryPoint: try arguments.requiredString("sequenceFrom"),
                maxDepth: arguments.int("maxDepth") ?? 5,
                map: arguments.stringArray("map"))
            return try SequenceDiagramTextExporter(request: request, theme: nil).export(from: artifact)
        case "state":
            let request = StateDiagramRequest(
                variable: try arguments.requiredString("stateFrom"),
                maxStates: arguments.int("maxStates") ?? 20)
            return try StateDiagramTextExporter(request: request, theme: nil).export(from: artifact)
        case "callgraph":
            let request = CallGraphRequest(scope: CallGraphScopeOption(raw: arguments.string("scope")))
            return try CallGraphTextExporter(request: request, theme: nil).export(from: artifact)
        default:
            throw MCPError.invalidParams("kind must be class, package, sequence, state, or callgraph.")
        }
    }

    private func classOptions(_ arguments: ToolArguments, language: LanguageConfiguration) -> ClassDiagramOptions {
        var options = ClassDiagramOptions(language: language)
        if let focus = arguments.string("focus") {
            options.focus = FocusConfiguration(
                rootTypeName: focus, maxDepth: arguments.int("focusDepth"), direction: .both)
            // A focused view is a local neighbourhood; grouping splits it into mismatched clusters.
            options.groupBy = .none
        }
        return options
    }
}
