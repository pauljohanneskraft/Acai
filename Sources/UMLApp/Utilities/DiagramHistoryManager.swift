import Foundation

/// A generic undo/redo history manager that stores snapshots of `Codable & Equatable` state.
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
    /// - Parameter snapshot: The state as it exists **right now**, before the change.
    func checkpoint(_ snapshot: Snapshot) {
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
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Redo one step: pushes `current` onto the undo stack and returns the next state.
    ///
    /// - Parameter current: The state **right now** (so it can be un-done again later).
    /// - Returns: The restored state, or `nil` if there is nothing to redo.
    func redo(current: Snapshot) -> Snapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    // MARK: - Reset

    /// Clears all undo and redo history.
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
