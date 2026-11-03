import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

@Suite("Activity interruption ledger: atlas export", .timeLimit(.minutes(1)))
@MainActor
struct ActivityCenterExportInterruptionTests {
    private let exportKind = ActivityOperation.Kind.other(systemImage: "doc.richtext")

    private func makeStore() -> InterruptedOperationStore {
        InterruptedOperationStore(
            baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func record(
        _ resumption: InterruptedOperationRecord.Resumption,
        kind: ActivityOperation.Kind = .reindex,
        startedAt: Date = Date()
    ) -> InterruptedOperationRecord {
        InterruptedOperationRecord(id: UUID(), kind: kind, resumption: resumption, startedAt: startedAt)
    }

    @Test("A relaunch over an interrupted atlas export offers to export it again")
    func anInterruptedAtlasExportIsReportedAfterRelaunch() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(
                title: "Exporting…", kind: exportKind, subject: .codebase(codebaseID),
                resumption: .exportAtlas(codebaseID: codebaseID)
            ) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { center.isBusy(.codebase(codebaseID)) }
        await center.flushPersistence()

        let relaunched = ActivityCenter(store: store)
        #expect(
            relaunched.interruptedOperation(forCodebase: codebaseID)?.resumption
                == .exportAtlas(codebaseID: codebaseID))

        await gate.open()
        _ = try await running.value
    }

    @Test("An interrupted reindex is reported ahead of a newer interrupted export, which follows once it is dismissed")
    func anInterruptedExportDoesNotHideOtherWork() throws {
        let store = makeStore()
        let codebaseID = UUID()
        let reindex = record(.reindex(codebaseID: codebaseID), startedAt: Date(timeIntervalSince1970: 1))
        let export = record(
            .exportAtlas(codebaseID: codebaseID), kind: exportKind, startedAt: Date(timeIntervalSince1970: 2))
        try store.save(ActivityLedger(inFlight: [reindex, export]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperations.map(\.id) == [reindex.id, export.id])
        #expect(center.interruptedOperation(forCodebase: codebaseID)?.resumption == .reindex(codebaseID: codebaseID))

        center.discardInterruptedOperation(reindex.id)
        #expect(
            center.interruptedOperation(forCodebase: codebaseID)?.resumption == .exportAtlas(codebaseID: codebaseID))
    }
}
