#if os(macOS)
import Foundation
import MCP
import AcaiLibrary
import AcaiRender

/// `acai_image` — renders a diagram to a PNG (base64 image content the agent can actually see), for
/// every diagram kind. macOS-only: rendering uses SwiftUI's `ImageRenderer`. Mirrors `acai image`.
/// Dispatches to the shared `AcaiRender` image exporters.
struct ImageTool: AnalysisTool {
    let name = "acai_image"
    let description = """
        Render a diagram of a codebase to a PNG image you can see: a class diagram (optionally focused), \
        a package/module graph, a sequence trace, a value-flow state machine, or a call graph. Use when \
        a visual is clearer than text (hairballs, layout, hot nodes). Pick with 'kind'. macOS only.
        """

    var inputSchema: Value {
        objectSchema(extraProperties: [
            "kind": [
                "type": "string",
                "enum": ["class", "package", "sequence", "state", "callgraph"],
                "description": "Diagram kind (default class)."
            ],
            "scale": ["type": "number", "description": "Output resolution scale factor (default 2)."],
            "theme": ["type": "string", "enum": ["default", "dark"], "description": "Colour theme (default light)."],
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
        do {
            let data = try await renderData(arguments, artifact: artifact)
            return .content([
                .image(data: data.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil)
            ])
        } catch let error as DiagramRequestError {
            throw MCPError.invalidParams(error.message)
        }
    }

    private func renderData(_ arguments: ToolArguments, artifact: CodeArtifact) async throws -> Data {
        let scale = try arguments.double("scale") ?? 2
        let palette: DiagramPalette = arguments.string("theme") == "dark" ? .dark : .light
        let languages = artifact.standardLanguageResolver
        switch arguments.string("kind") ?? "class" {
        case "class":
            return try await ClassImageExporter(
                scale: scale, palette: palette,
                configuration: try classConfiguration(arguments), languages: languages).render(artifact: artifact)
        case "package":
            return try await PackageImageExporter(
                scale: scale, palette: palette, languages: languages).render(artifact: artifact)
        case "sequence":
            return try await SequenceImageExporter(
                scale: scale, palette: palette,
                entryPoint: try arguments.requiredString("sequenceFrom"),
                maxDepth: try arguments.int("maxDepth") ?? 5,
                map: arguments.stringArray("map")).render(artifact: artifact)
        case "state":
            return try await StateImageExporter(
                scale: scale, palette: palette,
                variable: try arguments.requiredString("stateFrom"),
                maxStates: try arguments.int("maxStates") ?? 20).render(artifact: artifact)
        case "callgraph":
            return try await CallGraphImageExporter(
                scale: scale, palette: palette,
                scope: CallGraphScopeOption(raw: arguments.string("scope"))).render(artifact: artifact)
        default:
            throw MCPError.invalidParams("kind must be class, package, sequence, state, or callgraph.")
        }
    }

    private func classConfiguration(_ arguments: ToolArguments) throws -> ClassDiagramConfiguration {
        var configuration = ClassDiagramConfiguration()
        if let focus = arguments.string("focus") {
            configuration.focus = FocusConfiguration(
                rootTypeName: focus, maxDepth: try arguments.int("focusDepth"), direction: .both)
            configuration.grouping = .none
        }
        return configuration
    }
}
#endif
