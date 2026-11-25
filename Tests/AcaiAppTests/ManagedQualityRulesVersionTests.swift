import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

/// Both of the app's rules-file paths: the file its editor writes, and a file a codebase points at.
@Suite("App: rules file version", .timeLimit(.minutes(1)))
@MainActor
struct ManagedQualityRulesVersionTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-rules-version-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("The editor writes the current version into the file it saves")
    func savedRulesDeclareTheCurrentVersion() throws {
        try withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let url = try store.saveManagedRules(QualityRules(includeGeneratedTypes: true), forCodebase: UUID())
            let yaml = try String(contentsOf: url, encoding: .utf8)
            #expect(yaml.contains("version: \(QualityRules.currentVersion)"))
        }
    }

    @Test("A saved file reloads at the version it declares")
    func savedRulesRoundTripTheVersion() throws {
        try withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let codebaseID = UUID()
            try store.saveManagedRules(QualityRules(), forCodebase: codebaseID)
            #expect(store.loadManagedRules(forCodebase: codebaseID)?.version == QualityRules.currentVersion)
        }
    }

    @Test("A referenced file omitting the key reads as version 1")
    func referencedFileWithoutTheKeyReadsAsVersionOne() throws {
        try withTempStoreDir { dir in
            let url = try write("cycles:\n  scope: modules\n", in: dir)
            let rules = try QualityCheckConfiguration(rulesPath: url.path).loadRules()
            #expect(rules.version == 1)
        }
    }

    @Test("A referenced file from a newer Acai is refused, naming both versions")
    func referencedFileFromANewerBuildIsRefused() throws {
        try withTempStoreDir { dir in
            let newer = QualityRules.currentVersion + 1
            let url = try write("version: \(newer)\ncycles:\n  scope: modules\n", in: dir)
            let error = #expect(throws: UnsupportedRulesVersion.self) {
                try QualityCheckConfiguration(rulesPath: url.path).loadRules()
            }
            #expect(error?.found == newer)
            #expect(error?.supported == QualityRules.currentVersion)
            let expected = UnsupportedRulesVersion(found: newer, supported: QualityRules.currentVersion)
            #expect(error?.localizedDescription == expected.description)
        }
    }

    private func write(_ yaml: String, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("quality.yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
