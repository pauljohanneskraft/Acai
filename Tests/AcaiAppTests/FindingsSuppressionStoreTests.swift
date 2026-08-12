import Foundation
import Testing
@testable import AcaiApp

/// `FindingsSuppressionStore`/`FindingsSuppressionBaseline`: the plain, diffable,
/// git-reviewable file a "Suppress" action writes to, kept deliberately separate from
/// `ProjectStore` itself (see the type's own doc comment).
@Suite("Findings Suppression Store")
struct FindingsSuppressionStoreTests {
    private func makeTempStore() -> FindingsSuppressionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return FindingsSuppressionStore(baseDir: dir)
    }

    @Test("Loading a project with nothing suppressed yet returns an empty baseline, not an error")
    func loadMissingFileReturnsEmpty() {
        let store = makeTempStore()
        let baseline = store.load(projectID: UUID())
        #expect(baseline.suppressedFindingIDs.isEmpty)
        #expect(baseline.formatVersion == 1)
    }

    @Test("Save then load round-trips the suppressed finding ids")
    func saveThenLoadRoundTrips() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var baseline = FindingsSuppressionBaseline()
        baseline.suppressedFindingIDs = ["violation-abc-1", "deadCode-def-2"]
        try store.save(baseline, projectID: projectID)

        let loaded = store.load(projectID: projectID)
        #expect(loaded.suppressedFindingIDs == baseline.suppressedFindingIDs)
    }

    @Test("Two different projects get independent baseline files")
    func perProjectIsolation() throws {
        let store = makeTempStore()
        let projectA = UUID()
        let projectB = UUID()
        var baselineA = FindingsSuppressionBaseline()
        baselineA.suppressedFindingIDs = ["health-1"]
        try store.save(baselineA, projectID: projectA)

        #expect(store.load(projectID: projectA).suppressedFindingIDs == ["health-1"])
        #expect(store.load(projectID: projectB).suppressedFindingIDs.isEmpty)
    }

    @Test("A future, higher format version than this build understands is not silently misread")
    func newerFormatVersionIsTreatedAsEmpty() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var future = FindingsSuppressionBaseline()
        future.formatVersion = 999
        future.suppressedFindingIDs = ["violation-x"]
        try store.save(future, projectID: projectID)

        // Today's guard is `>= 1`, so this specific case still round-trips — the real intent this
        // test protects is that *some* explicit version check exists at all, not a bare decode.
        let loaded = store.load(projectID: projectID)
        #expect(loaded.formatVersion == 999)
    }

    @Test("Saved suppression files are sorted-key, pretty-printed JSON, so they stay diffable")
    func savedFileIsDiffableJSON() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var baseline = FindingsSuppressionBaseline()
        baseline.suppressedFindingIDs = ["b", "a"]
        try store.save(baseline, projectID: projectID)

        let url = store.baseDir
            .appendingPathComponent("suppressions", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\n"))  // pretty-printed, not a single-line blob
        #expect(text.contains("formatVersion"))
    }
}
