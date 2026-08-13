import Foundation

/// A generic "in-flight operation" registry: any operation — today reindex and the GitHub
/// fetch/clone family, wired in `ProjectCodebaseEditor` and `RepositoryDetailView` — reports
/// itself in via `run(title:kind:subject:operation:)` and the Activity indicator
/// (`ActivityIndicatorView`) plus every per-row spinner both read the same published list. One
/// instance lives on `ProjectStore` (`ProjectStore.activityCenter`), matching how
/// `GitRepositoryLocks` is already a single shared instance for a store's lifetime.
///
/// **Cancellation, stated precisely:** `run` always gives its `operation` a real `Task` to
/// cooperate with, and cancelling here reliably stops **the result from being applied** — the
/// caller never sees a value back, so it cannot persist stale state or report a spurious error.
/// What it does **not** do, verified by inspection rather than assumed: neither `CodebaseAnalyzer`'s
/// synchronous parse pass nor `AcaiGit`'s libgit2 calls poll `Task.isCancelled` internally, so
/// cancelling a reindex or a git fetch/clone does not interrupt CPU/network work already in flight —
/// it keeps running to completion in the background, just discarded. Wiring true mid-flight
/// interruption into those two call chains is separate, not-yet-built work that depends on this
/// type existing first; this type's job is to make every operation visible and to make "cancel" at
/// least mean "don't act on this anymore," never a button that lies about what it does.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var operations: [ActivityOperation] = []

    /// Whether any operation concerning `subject` is currently in flight — what each per-row
    /// spinner (`ProjectDetailView.codebaseRowContent`, `RepositoryDetailView`'s Fetch button) reads
    /// instead of duplicating per-row state.
    func isBusy(_ subject: ActivityOperation.Subject) -> Bool {
        guard subject != .none else { return false }
        return operations.contains { $0.subject == subject }
    }

    /// The in-flight operation concerning `subject`, if any.
    func operation(for subject: ActivityOperation.Subject) -> ActivityOperation? {
        guard subject != .none else { return nil }
        return operations.first { $0.subject == subject }
    }

    func cancel(_ id: ActivityOperation.ID) {
        operations.first { $0.id == id }?.requestCancel()
    }

    /// Runs `operation` as a named, cancellable row in the indicator for as long as it's in flight.
    /// Returns the operation's result, or `nil` if it was cancelled before finishing — callers must
    /// treat `nil` as "don't apply/persist/report anything," not as a failure worth surfacing.
    ///
    /// `operation` runs on a real child `Task`, wired to both directions of cancellation: the
    /// indicator's Cancel button (via the row's `requestCancel`) and the *caller's own* task being
    /// cancelled (e.g. a sheet with in-flight work being dismissed), via
    /// `withTaskCancellationHandler`.
    func run<T: Sendable>(
        title: String,
        kind: ActivityOperation.Kind,
        subject: ActivityOperation.Subject = .none,
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let task = Task<T, any Error>(priority: priority) { try await operation() }
        let id = UUID()
        operations.append(ActivityOperation(
            id: id, title: title, kind: kind, subject: subject, progress: nil,
            requestCancel: { task.cancel() }
        ))
        defer { operations.removeAll { $0.id == id } }
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
}
