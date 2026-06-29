import ArgumentParser
import Foundation
import UMLConformance
import Yams

extension ConformanceRules {
    /// Decodes a rules file. The model is `Codable`, so the YAML keys map directly onto the rule
    /// types (`forbidden`, `cycles`, `budgets`, `from`/`to`, `target`, `metric`, …). Decoding errors
    /// are wrapped in a `ValidationError` so the CLI surfaces a clean message, not a raw dump.
    static func load(yaml: String) throws -> ConformanceRules {
        do {
            return try YAMLDecoder().decode(ConformanceRules.self, from: yaml)
        } catch {
            throw ValidationError("Invalid rules file: \(error)")
        }
    }

    static func load(contentsOf path: String) throws -> ConformanceRules {
        let yaml = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return try load(yaml: yaml)
    }
}
