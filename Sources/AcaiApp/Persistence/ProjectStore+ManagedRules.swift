import AcaiQuality
import Foundation
import Yams

extension ProjectStore {
    func managedRulesURL(forCodebase codebaseID: UUID) -> URL {
        rulesDir.appendingPathComponent("codebase_\(codebaseID.uuidString).yaml")
    }

    /// Whether `path` points at a file the app manages (and so can be edited in the form), as opposed
    /// to an external file the user referenced. Compared on standardized paths so `..`/symlinks in the
    /// stored path don't fool the prefix check.
    func isManaged(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        let managed = rulesDir.standardizedFileURL.path
        return resolved == managed || resolved.hasPrefix(managed + "/")
    }

    @discardableResult
    func saveManagedRules(_ rules: QualityRules, forCodebase codebaseID: UUID) throws -> URL {
        let url = managedRulesURL(forCodebase: codebaseID)
        let yaml = try YAMLEncoder().encode(rules)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func loadManagedRules(forCodebase codebaseID: UUID) -> QualityRules? {
        let url = managedRulesURL(forCodebase: codebaseID)
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(QualityRules.self, from: yaml)
    }

    func deleteManagedRules(forCodebase codebaseID: UUID) {
        try? FileManager.default.removeItem(at: managedRulesURL(forCodebase: codebaseID))
    }
}
