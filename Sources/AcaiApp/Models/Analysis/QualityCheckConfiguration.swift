import Foundation
import AcaiQuality
import Yams

/// The persisted settings for a code-quality check: the path to its YAML rules file.
/// The check itself is recomputed from the codebase artifact each time the report is opened, so
/// only the rules-file location is stored (mirroring how `Codebase` stores a plain `directoryPath`).
///
/// The path is either an app-managed file (rules authored in the UI; see `ProjectStore.isManaged`)
/// or an external file the user pointed at — both are plain YAML, so evaluation treats them alike.
struct QualityCheckConfiguration: Codable, Hashable, Sendable {
    let rulesPath: String
    /// The security-scoped bookmark for an external file picked via `.fileImporter` on iOS (see
    /// `ScopedResourceAccess`). `nil` for app-managed files (always inside the app's own sandbox,
    /// no bookmark needed) and on macOS.
    var securityScopedBookmark: SecurityScopedBookmark?

    /// Loads and decodes the YAML rules at `rulesPath`. Throws if the file is missing or malformed.
    func loadRules() throws -> QualityRules {
        try ScopedResourceAccess(path: rulesPath, bookmark: securityScopedBookmark).withResolvedURL { url in
            let yaml = try String(contentsOf: url, encoding: .utf8)
            return try YAMLDecoder().decode(QualityRules.self, from: yaml)
        }
    }
}
