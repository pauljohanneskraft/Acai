import Foundation
import MCP

/// The set of analysis tools the server exposes, and the dispatch behind `tools/list` and
/// `tools/call`. Holds the shared snapshot cache so every tool call over one project reuses a single
/// parse.
struct ToolRegistry: Sendable {
    let tools: [any AnalysisTool]
    private let cache: AnalysisSnapshotCache

    init(tools: [any AnalysisTool], cache: AnalysisSnapshotCache = AnalysisSnapshotCache()) {
        self.tools = tools
        self.cache = cache
    }

    /// `acai_image` is appended on macOS only (it links the SwiftUI renderer), mirroring the CLI's
    /// `image` gating.
    static var standard: ToolRegistry {
        var tools: [any AnalysisTool] = [
            AnalyzeTool(),
            MetricsTool(),
            QualityTool(),
            CallGraphTool(),
            InspectTool(),
            ImpactTool(),
            DiffTool(),
            DiagramTool()
        ]
        #if os(macOS)
        tools.append(ImageTool())
        #endif
        return ToolRegistry(tools: tools)
    }

    var descriptors: [Tool] {
        tools.map { tool in
            Tool(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
                annotations: .init(readOnlyHint: true))
        }
    }

    func call(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw MCPError.methodNotFound("Unknown tool '\(name)'.")
        }
        switch try await tool.run(arguments: ToolArguments(arguments), cache: cache) {
        case .json(let value):
            return try CallTool.Result(
                content: [.text(text: prettyJSON(value), annotations: nil, _meta: nil)],
                structuredContent: value.asStructuredContent)
        case .content(let content):
            return CallTool.Result(content: content)
        }
    }

    @discardableResult
    func registerHandlers(on server: Server) async -> Server {
        await server
            .withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: descriptors) }
            .withMethodHandler(CallTool.self) { params in
                try await call(name: params.name, arguments: params.arguments)
            }
    }

    /// Matches the CLI's `JSONReport` output shape, so a tool call and its 1:1 CLI command read identically.
    private func prettyJSON(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
