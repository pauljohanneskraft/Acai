import Foundation
import Testing
@testable import AcaiApp

@Suite("MCPServerConfigSnippet")
struct MCPServerConfigSnippetTests {
    @Test("A plain path produces a valid mcpServers block with no args key")
    func plainPathProducesValidBlock() throws {
        let snippet = MCPServerConfigSnippet(serverName: "acai", binaryPath: "/usr/local/bin/acai-mcp")

        let object = try #require(decode(snippet.json))
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let acai = try #require(servers["acai"] as? [String: Any])
        #expect(acai["command"] as? String == "/usr/local/bin/acai-mcp")
        #expect(acai["args"] == nil)
    }

    @Test("Arguments are included when given, omitted when empty")
    func argumentsIncludedWhenGiven() throws {
        let withArgs = MCPServerConfigSnippet(
            serverName: "acai", binaryPath: "/usr/local/bin/acai-mcp", arguments: ["--verbose"])
        let object = try #require(decode(withArgs.json))
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let acai = try #require(servers["acai"] as? [String: Any])
        #expect(acai["args"] as? [String] == ["--verbose"])

        let withoutArgs = MCPServerConfigSnippet(serverName: "acai", binaryPath: "/usr/local/bin/acai-mcp")
        #expect(!withoutArgs.json.contains("args"))
    }

    @Test("The server name becomes the mcpServers key")
    func serverNameBecomesKey() throws {
        let snippet = MCPServerConfigSnippet(serverName: "acai-dev", binaryPath: "/tmp/AcaiMCP")

        let object = try #require(decode(snippet.json))
        let servers = try #require(object["mcpServers"] as? [String: Any])
        #expect(servers["acai-dev"] != nil)
        #expect(servers["acai"] == nil)
    }

    @Test("A path with characters that need JSON escaping still round-trips exactly")
    func pathNeedingEscapingRoundTrips() throws {
        let path = "/Users/alice/Library/Application Support/Acai \"builds\"/AcaiMCP"
        let snippet = MCPServerConfigSnippet(serverName: "acai", binaryPath: path)

        let object = try #require(decode(snippet.json))
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let acai = try #require(servers["acai"] as? [String: Any])
        #expect(acai["command"] as? String == path)
    }

    private func decode(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
