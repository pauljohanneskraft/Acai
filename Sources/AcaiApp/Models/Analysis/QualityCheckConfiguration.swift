import Foundation
import AcaiQuality
import Yams

/// The check itself is recomputed from the codebase artifact each time the report is opened, so
/// only the rules-file location is stored.
struct QualityCheckConfiguration: Codable, Hashable, Sendable {
    let rulesPath: String
    /// `nil` for app-managed files (always inside the app's own sandbox, no bookmark needed) and
    /// on macOS.
    var securityScopedBookmark: SecurityScopedBookmark?

    func loadRules() throws -> QualityRules {
        try ScopedResourceAccess(path: rulesPath, bookmark: securityScopedBookmark).withResolvedURL { url in
            let yaml = try String(contentsOf: url, encoding: .utf8)
            return try YAMLDecoder().decode(QualityRules.self, from: yaml)
        }
    }
}
