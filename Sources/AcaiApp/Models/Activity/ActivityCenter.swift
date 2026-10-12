import Foundation

/// **Cancellation:** `run` always gives its `operation` a real `Task` to cooperate with, so
/// cancelling here stops the work itself, not just whether its result gets applied.
///
/// **Interruption:** every operation with a subject is written to an `ActivityLedger` while it
/// runs and removed when it ends. Only a killed process skips that removal, so a record still
/// marked in flight at the next launch is exactly an operation termination interrupted —
/// republished as `interruptedOperations` for the screen that owns the subject to report.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var operations: [ActivityOperation] = []
    /// Work an earlier launch started and never finished, newest record per subject.
    @Published private(set) var interruptedOperations: [InterruptedOperationRecord] = []

    /// Routes a failed ledger write to whatever presents the app's other persistence failures,
    /// rather than leaving the user to discover that interruptions stopped being reported.
    var onPersistenceFailure: (@MainActor (any Error) -> Void)?

    private let store: InterruptedOperationStore?
    private var ledger = ActivityLedger()
    /// Each write awaits the one before it, so a newer ledger is never buried by an older
    /// snapshot that reached the disk later.
    private var lastWrite: Task<Void, Never>?

    /// A `nil` store keeps everything in memory — the shape a test wants unless it is about
    /// interruption itself.
    init(store: InterruptedOperationStore? = nil) {
        self.store = store
        guard let store else { return }
        let loaded = store.load()
        ledger = reconciled(loaded)
        interruptedOperations = ledger.interrupted
        // A launch that found nothing to reconcile has nothing to write back.
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

    func interruptedOperation(for subject: ActivityOperation.Subject) -> InterruptedOperationRecord? {
        guard subject != .none else { return nil }
        return interruptedOperations.first { $0.subject == subject }
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
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try await run(title: title, kind: kind, subject: subject, priority: priority) { _ in try await operation() }
    }

    /// Hands `operation` a progress sink it can call (from any thread) to drive the row's
    /// determinate progress bar instead of an indeterminate spinner. Reports are throttled via
    /// `ActivityProgressGate` so a callback firing on every packet doesn't queue a flood of
    /// main-actor hops.
    func run<T: Sendable>(
        title: LocalizedStringResource,
        kind: ActivityOperation.Kind,
        subject: ActivityOperation.Subject = .none,
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
        begin(registered)
        defer {
            operations.removeAll { $0.id == id }
            end(id)
        }
        return try await awaitCancellable(task)
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

    /// Awaits the ledger writes already scheduled, so a caller that needs the file to be on disk
    /// doesn't have to guess at the timing.
    func flushPersistence() async {
        await lastWrite?.value
    }

    // MARK: - Interruption Ledger

    /// Whatever the loaded ledger still calls in flight was running when the process stopped, so
    /// this launch reports it as unfinished instead.
    private func reconciled(_ loaded: ActivityLedger) -> ActivityLedger {
        var ledger = loaded
        ledger.interrupted = newestPerSubject(loaded.interrupted + loaded.inFlight)
        ledger.inFlight = []
        return ledger
    }

    /// One record per subject: a codebase whose index was interrupted five times has one
    /// unfinished operation to report, not five. A subject-less operation is dropped — it names
    /// nothing a screen could report it against, and nothing the user could resume.
    private func newestPerSubject(_ records: [InterruptedOperationRecord]) -> [InterruptedOperationRecord] {
        var newest: [ActivityOperation.Subject: InterruptedOperationRecord] = [:]
        for record in records where record.subject != .none {
            if let existing = newest[record.subject], existing.startedAt >= record.startedAt { continue }
            newest[record.subject] = record
        }
        return newest.values.sorted { $0.startedAt < $1.startedAt }
    }

    /// Records the operation as in flight, and clears any unfinished record for the same subject:
    /// starting the work again is how the user resolves the interruption.
    private func begin(_ operation: ActivityOperation) {
        guard operation.subject != .none else { return }
        ledger.interrupted.removeAll { $0.subject == operation.subject }
        ledger.inFlight.append(InterruptedOperationRecord(operation))
        interruptedOperations = ledger.interrupted
        persist()
    }

    /// Completion, failure and cancellation all land here — `run`'s `defer` runs in every case a
    /// live process can reach.
    private func end(_ id: ActivityOperation.ID) {
        guard ledger.inFlight.contains(where: { $0.id == id }) else { return }
        ledger.inFlight.removeAll { $0.id == id }
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
