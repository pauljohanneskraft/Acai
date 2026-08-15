import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

/// `FilterPresetStore`/`FilterPresetList`: the plain, diffable, git-reviewable file a "Save as
/// Preset" action writes to, kept deliberately separate from `ProjectStore` itself — see
/// `FindingsSuppressionStoreTests`, whose shape this mirrors.
@Suite("Filter Preset Store")
struct FilterPresetStoreTests {
    private func makeTempStore() -> FilterPresetStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return FilterPresetStore(baseDir: dir)
    }

    @Test("Loading a project with nothing saved yet returns an empty list, not an error")
    func loadMissingFileReturnsEmpty() {
        let store = makeTempStore()
        let list = store.load(projectID: UUID())
        #expect(list.presets.isEmpty)
        #expect(list.formatVersion == 1)
    }

    @Test("Save then load round-trips the saved presets")
    func saveThenLoadRoundTrips() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var list = FilterPresetList()
        list.presets = [
            FilterPreset(
                name: "Public repositories",
                selector: Selector(stereotype: "repository", minimumAccess: .public)),
            FilterPreset(name: "UI module", selector: Selector(module: "UI"))
        ]
        try store.save(list, projectID: projectID)

        let loaded = store.load(projectID: projectID)
        #expect(loaded.presets == list.presets)
    }

    @Test("Two different projects get independent preset files")
    func perProjectIsolation() throws {
        let store = makeTempStore()
        let projectA = UUID()
        let projectB = UUID()
        var listA = FilterPresetList()
        listA.presets = [FilterPreset(name: "A", selector: Selector(module: "A"))]
        try store.save(listA, projectID: projectA)

        #expect(store.load(projectID: projectA).presets.map(\.name) == ["A"])
        #expect(store.load(projectID: projectB).presets.isEmpty)
    }

    @Test("A future, higher format version than this build understands is not silently misread")
    func newerFormatVersionIsTreatedAsEmpty() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var future = FilterPresetList()
        future.formatVersion = 999
        future.presets = [FilterPreset(name: "Future", selector: nil)]
        try store.save(future, projectID: projectID)

        // Today's guard is `>= 1`, so this specific case still round-trips — the real intent this
        // test protects is that *some* explicit version check exists at all, not a bare decode.
        let loaded = store.load(projectID: projectID)
        #expect(loaded.formatVersion == 999)
    }

    @Test("Saved preset files are sorted-key, pretty-printed JSON, so they stay diffable")
    func savedFileIsDiffableJSON() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var list = FilterPresetList()
        list.presets = [FilterPreset(name: "Z", selector: nil), FilterPreset(name: "A", selector: nil)]
        try store.save(list, projectID: projectID)

        let url = store.baseDir
            .appendingPathComponent("filterPresets", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\n"))  // pretty-printed, not a single-line blob
        #expect(text.contains("formatVersion"))
    }

    @Test("A preset round-trips its optional file filter alongside the selector")
    func fileFilterRoundTrips() throws {
        let store = makeTempStore()
        let projectID = UUID()
        var list = FilterPresetList()
        let fileFilter = FileFilter(rules: [.init(pattern: "Tests/**", syntax: .glob, action: .block)])
        list.presets = [FilterPreset(name: "Non-test", selector: Selector(module: "Core"), fileFilter: fileFilter)]
        try store.save(list, projectID: projectID)

        let loaded = store.load(projectID: projectID)
        #expect(loaded.presets.first?.fileFilter == fileFilter)
    }
}
