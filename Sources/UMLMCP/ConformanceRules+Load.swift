import Foundation
import UMLConformance
import Yams

extension ConformanceRules {
    /// Decodes a rules file from YAML on disk. Mirrors the CLI's `load(contentsOf:)` so the MCP
    /// server can load the same rules files without depending on `UMLCLI`.
    static func loadFromFile(at path: String) throws -> ConformanceRules {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError.invalidPath(path)
        }
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(ConformanceRules.self, from: yaml)
    }
}
