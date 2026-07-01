import Foundation
import MCP

@main
struct UMLMCPServer {
    static func main() async throws {
        let cache = SnapshotCache()
        let dispatcher = ToolDispatcher(cache: cache)

        let server = Server(
            name: "uml",
            version: "1.0.0",
            capabilities: Server.Capabilities(
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPTools.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let result = await dispatcher.dispatch(name: params.name, arguments: params.arguments)
            return result
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
