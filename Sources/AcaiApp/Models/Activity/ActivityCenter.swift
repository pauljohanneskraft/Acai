import Foundation

/// **Cancellation:** `run` always gives its `operation` a real `Task` to cooperate with, so
/// cancelling here stops the work itself, not just whether its result gets applied.
///
/// **Interruption:** a resumable operation stays in the on-disk ledger while it runs, so one a killed
/// process never finished is reported at the next launch as `interruptedOperations`.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var operations: [ActivityOperation] = []
    /// Work an earlier launch started and never finished, oldest first.
    @Published private(set) var interruptedOperations: [InterruptedOperationRecord] = []

    /// Where a failed ledger write is reported.
    var onPersistenceFailure: (@MainActor (any Error) -> Void)?

    private let store: InterruptedOperationStore?
    private var ledger = ActivityLedger()
    /// Each write awaits the one before it, so an older snapshot never lands last.
    private var lastWrite: Task<Void, Never>?

    /// A `nil` store keeps the ledger in memory only.
    init(store: InterruptedOperationStore? = nil) {
        self.store = store
        guard let store else { return }
        let loaded = store.load()
        ledger = reconciled(loaded)
        interruptedOperations = ledger.interrupted
        if ledger != loaded { persist() }
    }

    func isBusy(_ subject: ActivityOperation.Subject) -> Bool {
        guard subject != .none else { return false }
        return operations.contains { $0.subject == subject }
    }

    func operation(for subject: ActivityOperation.Subject) -> ActivityOperation? {
        guard subject != .none else { return nil }
        return operations.first { $0.subject == subject }
    }

    func cancel(_ id: ActivityOperation.ID) {
        operations.first { $0.id == id }?.requestCancel()
    }

    /// Returns the operation's result, or `nil` if it was cancelled before finishing — callers must
    /// treat `nil` as "don't apply/persist/report anything," not as a failure worth surfacing.
    func run<T: Sendable>(
        title: LocalizedStringResource,
        kind: ActivityOperation.Kind,
        subject: ActivityOperation.Subject = .none,
        resumption: InterruptedOperationRecord.Resumption? = nil,
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try await run(
            title: title, kind: kind, subject: subject, resumption: resumption, priority: priority
        ) { _ in try await operation() }
    }

    /// Hands `operation` a progress sink it can call (from any thread) to drive the row's
    /// determinate progress bar instead of an indeterminate spinner. Reports are throttled via
    /// `ActivityProgressGate` so a callback firing on every packet doesn't queue a flood of
    /// main-actor hops. A `resumption` is what a relaunch offers if the process dies before this ends.
    func run<T: Sendable>(
        title: LocalizedStringResource,
        kind: ActivityOperation.Kind,
        subject: ActivityOperation.Subject = .none,
        resumption: InterruptedOperationRecord.Resumption? = nil,
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> T
    ) async throws -> T? {
        let id = UUID()
        let gate = ActivityProgressGate()
        let onProgress: @Sendable (Double) -> Void = { [weak self] progress in
            guard gate.advance(to: progress) else { return }
            Task(priority: priority) { @MainActor in self?.updateProgress(id, progress: progress) }
        }
        let task = Task<T, any Error>(priority: priority) { try await operation(onProgress) }
        let registered = ActivityOperation(
            id: id, title: title, kind: kind, subject: subject, progress: nil,
            requestCancel: { task.cancel() }
        )
        operations.append(registered)
        if let resumption {
            begin(InterruptedOperationRecord(
                id: id, kind: kind, resumption: resumption, startedAt: registered.startedAt))
        }
        var succeeded = false
        defer {
            operations.removeAll { $0.id == id }
            end(id, succeeded: succeeded)
        }
        let result = try await awaitCancellable(task)
        succeeded = result != nil
        return result
    }

    private func awaitCancellable<T: Sendable>(_ task: Task<T, any Error>) async throws -> T? {
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return task.isCancelled ? nil : value
        } catch {
            if task.isCancelled || error is CancellationError { return nil }
            throw error
        }
    }

    func updateProgress(_ id: ActivityOperation.ID, progress: Double?) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].progress = progress
    }

    /// Awaits the ledger writes already scheduled.
    func flushPersistence() async {
        await lastWrite?.value
    }

    // MARK: - Interruption Ledger

    /// The newest unfinished work on an existing codebase, for its screen to offer to resume.
    func interruptedOperation(forCodebase codebaseID: UUID) -> InterruptedOperationRecord? {
        interruptedOperations.last {
            if case .clone = $0.resumption { return false }
            return $0.resumption.codebaseID == codebaseID
        }
    }

    func interruptedClones(inProject projectID: UUID) -> [InterruptedOperationRecord] {
        interruptedOperations.filter {
            guard case .clone(let request) = $0.resumption else { return false }
            return request.projectID == projectID
        }
    }

    /// The user chose not to resume it.
    func discardInterruptedOperation(_ id: InterruptedOperationRecord.ID) {
        guard ledger.interrupted.contains(where: { $0.id == id }) else { return }
        ledger.interrupted.removeAll { $0.id == id }
        interruptedOperations = ledger.interrupted
        persist()
    }

    /// Drops records whose subject is gone: a deleted codebase or project, or a clone that did add its codebase.
    func pruneInterruptedOperations(existingCodebaseIDs: Set<UUID>, existingProjectIDs: Set<UUID>) {
        let kept = ledger.interrupted.filter { record in
            guard case .clone(let request) = record.resumption else {
                return existingCodebaseIDs.contains(record.resumption.codebaseID)
            }
            return existingProjectIDs.contains(request.projectID) && !existingCodebaseIDs.contains(request.codebaseID)
        }
        guard kept != ledger.interrupted else { return }
        ledger.interrupted = kept
        interruptedOperations = kept
        persist()
    }

    /// Whatever the loaded ledger still calls in flight was running when the process stopped.
    private func reconciled(_ loaded: ActivityLedger) -> ActivityLedger {
        var ledger = loaded
        ledger.interrupted = withoutSuperseded(loaded.interrupted + loaded.inFlight)
        ledger.inFlight = []
        return ledger
    }

    /// Oldest first, without any record that a newer one's resumption would also resolve.
    private func withoutSuperseded(_ records: [InterruptedOperationRecord]) -> [InterruptedOperationRecord] {
        var kept: [InterruptedOperationRecord] = []
        for record in records.sorted(by: { $0.startedAt > $1.startedAt })
        where !kept.contains(where: { $0.resumption.resolves(record.resumption) }) {
            kept.append(record)
        }
        return kept.reversed()
    }

    private func begin(_ record: InterruptedOperationRecord) {
        ledger.inFlight.append(record)
        persist()
    }

    /// Finishing also clears the unfinished records it leaves consistent again.
    private func end(_ id: ActivityOperation.ID, succeeded: Bool) {
        guard let record = ledger.inFlight.first(where: { $0.id == id }) else { return }
        ledger.inFlight.removeAll { $0.id == id }
        if succeeded {
            ledger.interrupted.removeAll { record.resumption.resolves($0.resumption) }
            interruptedOperations = ledger.interrupted
        }
        persist()
    }

    private func persist() {
        guard let store else { return }
        let ledger = ledger
        let previous = lastWrite
        lastWrite = Task { [weak self] in
            await previous?.value
            do {
                try await Task.detached(priority: .utility) { try store.save(ledger) }.value
            } catch {
                self?.onPersistenceFailure?(error)
            }
        }
    }
}
