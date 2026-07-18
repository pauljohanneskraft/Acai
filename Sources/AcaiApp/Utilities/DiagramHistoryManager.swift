import Foundation

/// A generic undo/redo history manager that stores snapshots of `Equatable & Sendable` state.
///
/// Usage:
/// 1. Call `checkpoint(_:)` **before** each meaningful mutation to record the current state.
/// 2. Call `undo(current:)` / `redo(current:)` to step backward / forward in history.
///
/// The manager deduplicates consecutive identical states and caps history at `maxHistory` entries.
@MainActor
final class DiagramHistoryManager<Snapshot: Equatable & Sendable> {

    // MARK: - Configuration

    /// Maximum number of undo snapshots to retain.
    private let maxHistory: Int

    // MARK: - State

    /// Stack of past states (most recent at the end). The top represents the state
    /// to restore when the user invokes undo.
    private var undoStack: [Snapshot] = []

    /// Stack of future states (most recent at the end). Populated when the user invokes undo;
    /// cleared on any new mutation.
    private var redoStack: [Snapshot] = []

    /// Coalescing key of the most recent `checkpoint`. Consecutive checkpoints that share a
    /// non-nil key are merged into one undo step; reset by `undo`/`redo`/`clear`.
    private var lastCoalescingKey: AnyHashable?

    /// Returns `true` when there is at least one state to undo to.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Returns `true` when there is at least one state to redo to.
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Init

    init(maxHistory: Int = 50) {
        self.maxHistory = maxHistory
    }

    // MARK: - Recording

    /// Record the **current** state as a checkpoint before applying a mutation.
    ///
    /// Call this at the **start** of every user-initiated action that you want to be undoable.
    /// For example, before deleting a node, pass the current snapshot so the user can
    /// undo back to it.
    ///
    /// - Parameters:
    ///   - snapshot: The state as it exists **right now**, before the change.
    ///   - coalescingKey: When non-nil and equal to the previous checkpoint's key, this
    ///     checkpoint is merged into the same undo step (e.g. consecutive keystrokes in one
    ///     text field). A different or `nil` key starts a new step.
    func checkpoint(_ snapshot: Snapshot, coalescingKey: AnyHashable? = nil) {
        // Merge consecutive checkpoints that share a non-nil coalescing key into one step.
        let continuesGroup = coalescingKey != nil && coalescingKey == lastCoalescingKey
        lastCoalescingKey = coalescingKey
        if continuesGroup { return }

        // Avoid pushing duplicate states.
        if let last = undoStack.last, last == snapshot { return }

        undoStack.append(snapshot)

        // Trim oldest entries when we exceed the cap.
        if undoStack.count > maxHistory {
            undoStack.removeFirst(undoStack.count - maxHistory)
        }

        // Any new action invalidates the redo stack.
        redoStack.removeAll()
    }

    // MARK: - Undo / Redo

    /// Undo one step: pushes `current` onto the redo stack and returns the previous state.
    ///
    /// - Parameter current: The state **right now** (so it can be re-done later).
    /// - Returns: The restored state, or `nil` if there is nothing to undo.
    func undo(current: Snapshot) -> Snapshot? {
        lastCoalescingKey = nil
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Redo one step: pushes `current` onto the undo stack and returns the next state.
    ///
    /// - Parameter current: The state **right now** (so it can be un-done again later).
    /// - Returns: The restored state, or `nil` if there is nothing to redo.
    func redo(current: Snapshot) -> Snapshot? {
        lastCoalescingKey = nil
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    // MARK: - Reset

    /// Clears all undo and redo history.
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastCoalescingKey = nil
    }
}

// MARK: - DiagramHistoryHosting

/// Adopted by view models that back undo/redo with a `DiagramHistoryManager`.
///
/// Conformers supply only `historySnapshot` (read = capture the current state, write = apply a
/// restored state) and, optionally, `persistAfterHistoryChange()`. The shared default
/// implementations provide `canUndo` / `canRedo` / `recordUndo` / `undo` / `redo`, so this
/// boilerplate lives in exactly one place.
@MainActor
protocol DiagramHistoryHosting: AnyObject {
    associatedtype Snapshot: Equatable & Sendable

    /// The backing history manager.
    var history: DiagramHistoryManager<Snapshot> { get }

    /// The undoable state: reading captures the current state, writing applies a restored one.
    var historySnapshot: Snapshot { get set }

    /// Hook invoked after `undo()` / `redo()` apply a restored snapshot. Defaults to a no-op
    /// (the view is responsible for persistence); override to self-persist.
    func persistAfterHistoryChange()
}

extension DiagramHistoryHosting {
    func persistAfterHistoryChange() {}

    /// Whether there is a state to undo to.
    var canUndo: Bool { history.canUndo }

    /// Whether there is a state to redo to.
    var canRedo: Bool { history.canRedo }

    /// Capture the current state as a checkpoint before a mutation.
    ///
    /// Call this at the **start** of every undoable action (and once, before positions change,
    /// at the start of a drag/resize gesture).
    ///
    /// - Parameter coalescingKey: When non-nil and equal to the previous checkpoint's key, the
    ///   checkpoint is merged into the same undo step (e.g. consecutive keystrokes in one text
    ///   field). Pass `nil` (the default) for discrete actions.
    func recordUndo(coalescingKey: AnyHashable? = nil) {
        history.checkpoint(historySnapshot, coalescingKey: coalescingKey)
    }

    /// Undo the last action, restoring the previous state.
    func undo() {
        guard let previous = history.undo(current: historySnapshot) else { return }
        historySnapshot = previous
        persistAfterHistoryChange()
    }

    /// Redo the last undone action.
    func redo() {
        guard let next = history.redo(current: historySnapshot) else { return }
        historySnapshot = next
        persistAfterHistoryChange()
    }
}
