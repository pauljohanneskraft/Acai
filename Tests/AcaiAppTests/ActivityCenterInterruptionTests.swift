import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

/// A killed process never reaches `run`'s `defer`, so these read or seed the ledger a relaunch finds.
@Suite("Activity interruption ledger", .timeLimit(.minutes(1)))
@MainActor
struct ActivityCenterInterruptionTests {
    private struct Failure: Error {}

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

    private func cloneRequest(projectID: UUID = UUID()) -> InterruptedOperationRecord.RemoteCloneRequest {
        InterruptedOperationRecord.RemoteCloneRequest(
            projectID: projectID, codebaseID: UUID(), name: "widgets",
            remoteURL: URL(fileURLWithPath: "/tmp/widgets.git"), ref: "main", refKind: .branch,
            latestSnapshotOnly: false)
    }

    @Test("A relaunch over a ledger left mid-operation reports that operation as unfinished")
    func anInFlightRecordIsReportedAfterRelaunch() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(
                title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID),
                resumption: .reindex(codebaseID: codebaseID)
            ) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { center.isBusy(.codebase(codebaseID)) }
        await center.flushPersistence()

        let relaunched = ActivityCenter(store: store)
        #expect(
            relaunched.interruptedOperation(forCodebase: codebaseID)?.resumption == .reindex(codebaseID: codebaseID))
        #expect(relaunched.operations.isEmpty)

        await gate.open()
        _ = try await running.value
    }

    @Test("An operation that finishes leaves the next launch nothing to report")
    func completionClearsTheRecord() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let center = ActivityCenter(store: store)
        _ = try await center.run(title: "Indexing…", kind: .reindex, resumption: .reindex(codebaseID: codebaseID)) { 1 }
        await center.flushPersistence()

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("A cancelled operation leaves nothing either — the user stopping work is not an interruption")
    func cancellationClearsTheRecord() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(title: "Indexing…", kind: .reindex, resumption: .reindex(codebaseID: codebaseID)) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { !center.operations.isEmpty }
        let operation = try #require(center.operations.first)
        center.cancel(operation.id)
        await gate.open()
        #expect(try await running.value == nil)
        await center.flushPersistence()

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("Finishing the work again resolves the interruption it resumes")
    func finishingTheResumedWorkClearsItsRecord() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        try store.save(ActivityLedger(inFlight: [record(.reindex(codebaseID: codebaseID))]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperation(forCodebase: codebaseID) != nil)
        _ = try await center.run(title: "Indexing…", kind: .reindex, resumption: .reindex(codebaseID: codebaseID)) { 1 }

        #expect(center.interruptedOperation(forCodebase: codebaseID) == nil)
        await center.flushPersistence()
        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("A retry that fails leaves the interruption reported")
    func aFailedRetryKeepsTheRecord() async throws {
        let codebaseID = UUID()
        let store = makeStore()
        try store.save(ActivityLedger(inFlight: [record(.reindex(codebaseID: codebaseID))]))
        let center = ActivityCenter(store: store)

        await #expect(throws: Failure.self) {
            try await center.run(
                title: "Indexing…", kind: .reindex, resumption: .reindex(codebaseID: codebaseID)
            ) { () async throws -> Int in throw Failure() }
        }

        #expect(center.interruptedOperation(forCodebase: codebaseID) != nil)
    }

    @Test("Only the work that makes a codebase consistent again resolves its interruption")
    func resumptionsResolveOnlyWhatTheyRedo() {
        let codebase = UUID()
        let reindex = InterruptedOperationRecord.Resumption.reindex(codebaseID: codebase)
        let pull = InterruptedOperationRecord.Resumption.pull(codebaseID: codebase)
        let switchRef = InterruptedOperationRecord.Resumption.switchRef(
            codebaseID: codebase, ref: "dev", refKind: .branch)

        #expect(reindex.resolves(reindex))
        #expect(!reindex.resolves(pull))
        #expect(pull.resolves(pull))
        #expect(!pull.resolves(reindex))
        #expect(!pull.resolves(switchRef))
        #expect(switchRef.resolves(pull))
        #expect(switchRef.resolves(.switchRef(codebaseID: codebase, ref: "main", refKind: .branch)))
        #expect(!reindex.resolves(.reindex(codebaseID: UUID())))
    }

    @Test("An unfinished operation for one codebase says nothing about another")
    func recordsAreReportedPerCodebase() throws {
        let store = makeStore()
        let interrupted = UUID()
        try store.save(ActivityLedger(inFlight: [record(.pull(codebaseID: interrupted), kind: .gitFetch)]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperation(forCodebase: interrupted)?.resumption == .pull(codebaseID: interrupted))
        #expect(center.interruptedOperation(forCodebase: UUID()) == nil)
    }

    @Test("A repeated interruption is reported once, but one a newer record wouldn't redo is kept")
    func supersededRecordsAreDropped() throws {
        let store = makeStore()
        let codebaseID = UUID()
        let older = record(.reindex(codebaseID: codebaseID), startedAt: Date(timeIntervalSince1970: 1))
        let newer = record(.reindex(codebaseID: codebaseID), startedAt: Date(timeIntervalSince1970: 2))
        let newestPull = record(
            .pull(codebaseID: codebaseID), kind: .gitFetch, startedAt: Date(timeIntervalSince1970: 3))
        try store.save(ActivityLedger(inFlight: [newer, newestPull], interrupted: [older]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperations.map(\.id) == [newer.id, newestPull.id])
        #expect(center.interruptedOperation(forCodebase: codebaseID)?.id == newestPull.id)
    }

    @Test("Work with nothing to resume, like an export, is never recorded")
    func operationsWithoutAResumptionAreNotRecorded() async throws {
        let store = makeStore()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(title: "Exporting…", kind: .other(systemImage: "doc"), subject: .codebase(UUID())) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { !center.operations.isEmpty }
        await center.flushPersistence()

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)

        await gate.open()
        _ = try await running.value
    }

    @Test("An interrupted clone is reported on its project, never as a codebase's")
    func anInterruptedCloneBelongsToItsProject() throws {
        let store = makeStore()
        let request = cloneRequest()
        try store.save(ActivityLedger(inFlight: [record(.clone(request), kind: .gitClone)]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedClones(inProject: request.projectID).map(\.resumption) == [.clone(request)])
        #expect(center.interruptedClones(inProject: UUID()).isEmpty)
        #expect(center.interruptedOperation(forCodebase: request.codebaseID) == nil)
    }

    @Test("Records whose subject is gone are pruned; the rest stay")
    func recordsForMissingSubjectsArePruned() async throws {
        let store = makeStore()
        let kept = UUID()
        let project = UUID()
        let liveClone = cloneRequest(projectID: project)
        let cloneOfDeletedProject = cloneRequest()
        let finishedClone = cloneRequest(projectID: project)
        try store.save(ActivityLedger(interrupted: [
            record(.reindex(codebaseID: kept)),
            record(.reindex(codebaseID: UUID())),
            record(.clone(liveClone), kind: .gitClone),
            record(.clone(cloneOfDeletedProject), kind: .gitClone),
            record(.clone(finishedClone), kind: .gitClone)
        ]))

        let center = ActivityCenter(store: store)
        center.pruneInterruptedOperations(
            existingCodebaseIDs: [kept, finishedClone.codebaseID], existingProjectIDs: [project])

        #expect(center.interruptedOperations.map(\.resumption) == [.reindex(codebaseID: kept), .clone(liveClone)])
        await center.flushPersistence()
        #expect(ActivityCenter(store: store).interruptedOperations.count == 2)
    }

    @Test("Dismissing an interruption forgets it across launches")
    func discardingRemovesTheRecord() async throws {
        let store = makeStore()
        let interrupted = record(.clone(cloneRequest()), kind: .gitClone)
        try store.save(ActivityLedger(interrupted: [interrupted]))

        let center = ActivityCenter(store: store)
        center.discardInterruptedOperation(interrupted.id)
        #expect(center.interruptedOperations.isEmpty)
        await center.flushPersistence()
        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("A ledger written in a format this build doesn't know is dropped, not misread")
    func anUnknownFormatVersionIsDropped() throws {
        let store = makeStore()
        var future = ActivityLedger(inFlight: [record(.reindex(codebaseID: UUID()))])
        future.formatVersion = ActivityLedger.currentFormatVersion + 1
        try store.save(future)

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("The ledger round-trips both halves through its file")
    func theLedgerRoundTripsThroughDisk() throws {
        let store = makeStore()
        let ledger = ActivityLedger(
            inFlight: [record(.reindex(codebaseID: UUID()), startedAt: Date(timeIntervalSince1970: 1))],
            interrupted: [record(.clone(cloneRequest()), kind: .gitClone, startedAt: Date(timeIntervalSince1970: 2))])
        try store.save(ledger)

        #expect(store.load() == ledger)
    }

    @Test("A ledger that was never written reads as empty rather than failing")
    func aMissingLedgerReadsAsEmpty() {
        #expect(makeStore().load() == ActivityLedger())
    }
}
