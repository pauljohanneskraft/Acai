import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

/// The ledger behind "an operation interrupted by termination leaves recoverable state". A killed
/// process is the one case `run`'s `defer` never reaches, so every test here either holds an
/// operation open and reads the file a relaunch would find, or seeds that file directly — there is
/// no way to assert this from in-memory state alone.
@Suite("Activity interruption ledger", .timeLimit(.minutes(1)))
@MainActor
struct ActivityCenterInterruptionTests {
    private func makeStore() -> InterruptedOperationStore {
        InterruptedOperationStore(
            baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func record(
        kind: ActivityOperation.Kind = .reindex,
        subject: ActivityOperation.Subject,
        startedAt: Date = Date()
    ) -> InterruptedOperationRecord {
        InterruptedOperationRecord(id: UUID(), kind: kind, subject: subject, startedAt: startedAt)
    }

    @Test("A relaunch over a ledger left mid-operation reports that operation as unfinished")
    func anInFlightRecordIsReportedAfterRelaunch() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID)) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { center.isBusy(.codebase(codebaseID)) }
        await center.flushPersistence()

        // Termination happens here: the ledger is on disk with the operation still in flight, and
        // nothing ran `run`'s `defer`.
        let relaunched = ActivityCenter(store: store)
        #expect(relaunched.interruptedOperation(for: .codebase(codebaseID))?.kind == .reindex)
        #expect(relaunched.operations.isEmpty)

        await gate.open()
        _ = try await running.value
    }

    @Test("An operation that finishes leaves the next launch nothing to report")
    func completionClearsTheRecord() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        let center = ActivityCenter(store: store)
        _ = try await center.run(title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID)) { 1 }
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
            try await center.run(title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID)) {
                await gate.wait()
                return 1
            }
        }
        try await Eventually().waitUntil("the operation is registered") { !center.operations.isEmpty }
        guard let operation = center.operations.first else {
            Issue.record("expected an in-flight operation to be registered")
            return
        }
        center.cancel(operation.id)
        await gate.open()
        #expect(try await running.value == nil)
        await center.flushPersistence()

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("Starting the work again resolves the interruption it is resuming")
    func beginningAnOperationClearsItsSubjectsRecord() async throws {
        let store = makeStore()
        let codebaseID = UUID()
        try store.save(ActivityLedger(inFlight: [record(subject: .codebase(codebaseID))]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperation(for: .codebase(codebaseID)) != nil)
        _ = try await center.run(title: "Indexing…", kind: .reindex, subject: .codebase(codebaseID)) { 1 }

        #expect(center.interruptedOperation(for: .codebase(codebaseID)) == nil)
        await center.flushPersistence()
        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("An unfinished operation for one codebase says nothing about another")
    func recordsAreReportedPerSubject() throws {
        let store = makeStore()
        let interrupted = UUID()
        let untouched = UUID()
        try store.save(ActivityLedger(inFlight: [record(kind: .gitClone, subject: .codebase(interrupted))]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperation(for: .codebase(interrupted))?.kind == .gitClone)
        #expect(center.interruptedOperation(for: .codebase(untouched)) == nil)
    }

    @Test("A subject repeatedly interrupted reports its newest unfinished operation, once")
    func onlyTheNewestRecordPerSubjectIsReported() throws {
        let store = makeStore()
        let codebaseID = UUID()
        let older = record(kind: .gitFetch, subject: .codebase(codebaseID), startedAt: Date(timeIntervalSince1970: 1))
        let newer = record(kind: .reindex, subject: .codebase(codebaseID), startedAt: Date(timeIntervalSince1970: 2))
        try store.save(ActivityLedger(inFlight: [newer], interrupted: [older]))

        let center = ActivityCenter(store: store)
        #expect(center.interruptedOperations.count == 1)
        #expect(center.interruptedOperation(for: .codebase(codebaseID))?.id == newer.id)
    }

    @Test("A subject-less operation is never recorded: nothing could report it or resume it")
    func subjectLessOperationsAreNotRecorded() async throws {
        let store = makeStore()
        let gate = AsyncGate()
        let center = ActivityCenter(store: store)
        let running = Task {
            try await center.run(title: "Exporting…", kind: .other(systemImage: "doc")) {
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

    @Test("A ledger written in a format this build doesn't know is dropped, not misread")
    func anUnknownFormatVersionIsDropped() throws {
        let store = makeStore()
        var future = ActivityLedger(inFlight: [record(subject: .codebase(UUID()))])
        future.formatVersion = ActivityLedger.currentFormatVersion + 1
        try store.save(future)

        #expect(ActivityCenter(store: store).interruptedOperations.isEmpty)
    }

    @Test("The ledger round-trips both halves through its file")
    func theLedgerRoundTripsThroughDisk() throws {
        let store = makeStore()
        let ledger = ActivityLedger(
            inFlight: [record(subject: .codebase(UUID()), startedAt: Date(timeIntervalSince1970: 1))],
            interrupted: [record(
                kind: .gitFetch, subject: .repository(URL(fileURLWithPath: "/tmp/hub.git")),
                startedAt: Date(timeIntervalSince1970: 2))])
        try store.save(ledger)

        #expect(store.load() == ledger)
    }

    @Test("A ledger that was never written reads as empty rather than failing")
    func aMissingLedgerReadsAsEmpty() {
        #expect(makeStore().load() == ActivityLedger())
    }
}
