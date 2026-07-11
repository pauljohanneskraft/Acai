import Foundation
import UMLQuality
import Yams

/// The persisted settings for a code-quality check: the path to its YAML rules file.
/// The check itself is recomputed from the codebase artifact each time the report is opened, so
/// only the rules-file location is stored (mirroring how `Codebase` stores a plain `directoryPath`).
///
/// The path is either an app-managed file (rules authored in the UI; see `ProjectStore.isManaged`)
/// or an external file the user pointed at — both are plain YAML, so evaluation treats them alike.
struct QualityCheckConfiguration: Codable, Hashable, Sendable {
    let rulesPath: String

    /// Loads and decodes the YAML rules at `rulesPath`. Throws if the file is missing or malformed.
    func loadRules() throws -> QualityRules {
        let yaml = try String(contentsOf: URL(fileURLWithPath: rulesPath), encoding: .utf8)
        return try YAMLDecoder().decode(QualityRules.self, from: yaml)
    }
}
