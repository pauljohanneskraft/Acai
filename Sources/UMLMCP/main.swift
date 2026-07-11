import MCP

// The UML MCP server: a third entry point over `UMLLibrary` (like the CLI and the app), exposing the
// read-only analysis engine to an MCP client over JSON-RPC/stdio. Everything runs in-process — there
// is no `uml` binary to find on `PATH` and no subprocess. The tool set is intentionally small so an
// always-on server adds little to each session's context.
let registry = ToolRegistry.standard

let server = Server(
    name: "uml",
    version: "0.1.0",
    instructions: """
        Read-only code-structure analysis over eight languages. Reach for these when reasoning about \
        an unfamiliar or large codebase: uml_analyze to index a project (set health to check the parse \
        is trustworthy before relying on the rest), then uml_metrics for the raw numbers and \
        uml_quality to find architectural debt, god classes, and code smells (or gate a rules file). \
        uml_callgraph reports method-level metrics, cycles, or dead code; uml_impact gauges whether a \
        change is safe; uml_inspect locates types, members, and enums. Every result carries file:line \
        jump targets.
        """,
    capabilities: .init(tools: .init(listChanged: false)))

await registry.registerHandlers(on: server)

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
