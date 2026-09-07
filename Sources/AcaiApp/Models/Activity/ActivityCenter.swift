import Foundation

/// **Cancellation:** `run` always gives its `operation` a real `Task` to cooperate with, so
/// cancelling here stops the work itself, not just whether its result gets applied.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var operations: [ActivityOperation] = []

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
