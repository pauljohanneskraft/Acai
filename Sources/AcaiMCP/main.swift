import MCP

let registry = ToolRegistry.standard

let server = Server(
    name: "acai",
    version: "0.1.0",
    instructions: """
        Read-only code-structure analysis over eight languages. Reach for these when reasoning about \
        an unfamiliar or large codebase: acai_analyze to index a project (set health to check the parse \
        is trustworthy before relying on the rest), then acai_metrics for the raw numbers and \
        acai_quality to find architectural debt, god classes, and code smells (or gate a rules file). \
        acai_callgraph reports method-level metrics, cycles, or dead code; acai_impact gauges whether a \
        change is safe; acai_inspect locates types, members, and enums. Every result carries file:line \
        jump targets.
        """,
    capabilities: .init(tools: .init(listChanged: false)))

await registry.registerHandlers(on: server)

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
