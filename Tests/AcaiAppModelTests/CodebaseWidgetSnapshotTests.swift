import Foundation
import Testing
@testable import AcaiAppModel

/// `CodebaseWidgetSnapshot`/`CodebaseWidgetSnapshotList`/`CodebaseWidgetSnapshotStore`: the
/// codebase state the app shares with the widget extension through the App Group container.
@Suite("CodebaseWidgetSnapshot")
struct CodebaseWidgetSnapshotTests {
    private let first = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func store() throws -> CodebaseWidgetSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("widget-snapshot-\(UUID().uuidString)", isDirectory: true)
        return CodebaseWidgetSnapshotStore(containerURL: directory)
    }

    @Test("A snapshot's address is its codebase's deep link, so a tap opens the codebase shown")
    func addressIsTheCodebaseDeepLink() {
        let snapshot = CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai")
        #expect(snapshot.address == .codebase(first))
        #expect(snapshot.address.url.absoluteString == "acai://codebase/\(first.uuidString)")
    }

    @Test("A never-analysed codebase reports no analysis rather than a zero date")
    func neverAnalysedReportsNoAnalysis() {
        let snapshot = CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai")
        #expect(!snapshot.hasBeenAnalysed)
        #expect(snapshot.analysedAt == nil)
        #expect(!snapshot.isOutOfDate)
        #expect(snapshot.freshnessCheckedAt == nil)
    }

    @Test("Saving then loading round-trips every field")
    func saveLoadRoundTrip() throws {
        let store = try store()
        let analysedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_900)
        let snapshot = CodebaseWidgetSnapshot(
            codebaseID: first, codebaseName: "Acai", analysedAt: analysedAt, analysedRevision: "abc123",
            isOutOfDate: true, freshnessCheckedAt: checkedAt, typeCount: 42, findingCount: 7,
            criticalFindingCount: 2, hasParseErrors: true)
        try store.save(CodebaseWidgetSnapshotList(snapshots: [snapshot]))

        #expect(store.load().snapshots == [snapshot])
    }

    @Test("Loading before anything was saved yields an empty list, not an error")
    func loadingNothingYieldsEmptyList() throws {
        #expect(try store().load().snapshots.isEmpty)
    }

    @Test("A file that can't be decoded is dropped, leaving the widget's empty state")
    func undecodableFileIsDropped() throws {
        let store = try store()
        try FileManager.default.createDirectory(at: store.containerURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL, options: .atomic)

        #expect(store.load().snapshots.isEmpty)
    }

    @Test("A file written by a newer app is dropped rather than half-read")
    func newerFormatVersionIsDropped() throws {
        let store = try store()
        var list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai"),
        ])
        list.formatVersion = CodebaseWidgetSnapshotList.currentFormatVersion + 1
        try store.save(list)

        #expect(store.load().snapshots.isEmpty)
    }

    @Test("Updating one codebase's entry leaves the others, so a reindex doesn't drop them")
    func updateLeavesOtherCodebases() {
        var list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai"),
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other"),
        ])
        list.update(CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai", typeCount: 9))

        #expect(list.snapshots.count == 2)
        #expect(list.snapshot(for: first)?.typeCount == 9)
        #expect(list.snapshot(for: second)?.codebaseName == "Other")
    }

    @Test("Updating a codebase the list has never seen appends it")
    func updateAppendsUnknownCodebase() {
        var list = CodebaseWidgetSnapshotList()
        list.update(CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai"))

        #expect(list.snapshot(for: first)?.codebaseName == "Acai")
    }

    @Test("A deleted codebase is pruned so the widget stops offering it")
    func deletedCodebaseIsPruned() {
        var list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai"),
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other"),
        ])
        list.removeAll(except: [second])

        #expect(list.snapshots.map(\.codebaseID) == [second])
    }

    @Test("A save overwrites the previous file rather than appending to it")
    func saveOverwrites() throws {
        let store = try store()
        try store.save(CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai"),
        ]))
        try store.save(CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other"),
        ]))

        #expect(store.load().snapshots.map(\.codebaseID) == [second])
    }
}
