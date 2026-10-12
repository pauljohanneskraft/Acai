import Foundation
import Testing
@testable import AcaiAppModel

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
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai")
        ])
        list.formatVersion = CodebaseWidgetSnapshotList.currentFormatVersion + 1
        try store.save(list)

        #expect(store.load().snapshots.isEmpty)
    }

    @Test("A save overwrites the previous file rather than appending to it")
    func saveOverwrites() throws {
        let store = try store()
        try store.save(CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai")
        ]))
        try store.save(CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other")
        ]))

        #expect(store.load().snapshots.map(\.codebaseID) == [second])
    }
}

@Suite("CodebaseWidgetSnapshotList merging")
struct CodebaseWidgetSnapshotMergingTests {
    private let first = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let analysed = Date(timeIntervalSince1970: 1_700_000_000)
    private let checked = Date(timeIntervalSince1970: 1_700_000_500)

    @Test("Counts recorded for the same analysis survive a write that doesn't know them")
    func countsSurviveAFreshnessOnlyWrite() {
        let list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(
                codebaseID: first, codebaseName: "Acai", analysedAt: analysed, typeCount: 12,
                findingCount: 3, criticalFindingCount: 1)
        ])
        let merged = list.merging([
            CodebaseWidgetSnapshot(
                codebaseID: first, codebaseName: "Acai", analysedAt: analysed, isOutOfDate: true,
                freshnessCheckedAt: checked)
        ])

        let snapshot = merged.snapshot(for: first)
        #expect(snapshot?.typeCount == 12)
        #expect(snapshot?.findingCount == 3)
        #expect(snapshot?.criticalFindingCount == 1)
        #expect(snapshot?.isOutOfDate == true)
        #expect(snapshot?.freshnessCheckedAt == checked)
    }

    @Test("Freshness recorded for the same analysis survives a write that only knows the counts")
    func freshnessSurvivesACountsOnlyWrite() {
        let list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(
                codebaseID: first, codebaseName: "Acai", analysedAt: analysed, isOutOfDate: true,
                freshnessCheckedAt: checked)
        ])
        let merged = list.merging([
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai", analysedAt: analysed, typeCount: 12)
        ])

        #expect(merged.snapshot(for: first)?.isOutOfDate == true)
        #expect(merged.snapshot(for: first)?.freshnessCheckedAt == checked)
        #expect(merged.snapshot(for: first)?.typeCount == 12)
    }

    @Test("A reindex drops the previous analysis's counts instead of carrying them forward")
    func reindexDropsStaleCounts() {
        let list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(
                codebaseID: first, codebaseName: "Acai", analysedAt: analysed, isOutOfDate: true,
                freshnessCheckedAt: checked, typeCount: 12, findingCount: 3)
        ])
        let merged = list.merging([
            CodebaseWidgetSnapshot(
                codebaseID: first, codebaseName: "Acai", analysedAt: analysed.addingTimeInterval(60))
        ])

        let snapshot = merged.snapshot(for: first)
        #expect(snapshot?.typeCount == nil)
        #expect(snapshot?.findingCount == nil)
        #expect(snapshot?.isOutOfDate == false)
        #expect(snapshot?.freshnessCheckedAt == nil)
    }

    @Test("A codebase the app no longer has is dropped")
    func deletedCodebaseIsDropped() {
        let list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai", analysedAt: analysed),
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other", analysedAt: analysed)
        ])
        let merged = list.merging([
            CodebaseWidgetSnapshot(codebaseID: second, codebaseName: "Other", analysedAt: analysed)
        ])

        #expect(merged.snapshots.map(\.codebaseID) == [second])
    }

    @Test("A renamed codebase takes the new name, not the stored one")
    func renameTakesEffect() {
        let list = CodebaseWidgetSnapshotList(snapshots: [
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Old", analysedAt: analysed, typeCount: 12)
        ])
        let merged = list.merging([
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "New", analysedAt: analysed)
        ])

        #expect(merged.snapshot(for: first)?.codebaseName == "New")
        #expect(merged.snapshot(for: first)?.typeCount == 12)
    }

    @Test("A codebase the list has never seen is added as it arrives")
    func newCodebaseIsAdded() {
        let merged = CodebaseWidgetSnapshotList().merging([
            CodebaseWidgetSnapshot(codebaseID: first, codebaseName: "Acai")
        ])

        #expect(merged.snapshots.map(\.codebaseName) == ["Acai"])
    }
}
