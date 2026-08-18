import Foundation

/// A generic undo/redo history manager that stores snapshots of `Equatable & Sendable` state.
///
/// Call `checkpoint(_:)` before each meaningful mutation to record the current state, then
/// `undo(current:)`/`redo(current:)` to step backward/forward. Deduplicates consecutive identical
/// states and caps history at `maxHistory` entries.
@MainActor
final class DiagramHistoryManager<Snapshot: Equatable & Sendable> {

    // MARK: - Configuration

    private let maxHistory: Int

    // MARK: - State

    private var undoStack: [Snapshot] = []
    /// Cleared on any new mutation.
    private var redoStack: [Snapshot] = []
    /// Consecutive checkpoints sharing a non-nil key merge into one undo step; reset by
    /// `undo`/`redo`/`clear`.
    private var lastCoalescingKey: AnyHashable?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Init

    init(maxHistory: Int = 50) {
        self.maxHistory = maxHistory
    }

    // MARK: - Recording

    /// - Parameter coalescingKey: When non-nil and equal to the previous checkpoint's key, merges
    ///   into the same undo step (e.g. consecutive keystrokes in one text field).
    func checkpoint(_ snapshot: Snapshot, coalescingKey: AnyHashable? = nil) {
        let continuesGroup = coalescingKey != nil && coalescingKey == lastCoalescingKey
        lastCoalescingKey = coalescingKey
        if continuesGroup { return }
        if let last = undoStack.last, last == snapshot { return }

        undoStack.append(snapshot)
        if undoStack.count > maxHistory {
            undoStack.removeFirst(undoStack.count - maxHistory)
        }
        redoStack.removeAll()
    }

    // MARK: - Undo / Redo

    func undo(current: Snapshot) -> Snapshot? {
        lastCoalescingKey = nil
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(current: Snapshot) -> Snapshot? {
        lastCoalescingKey = nil
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    // MARK: - Reset

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastCoalescingKey = nil
    }
}

// MARK: - DiagramHistoryHosting

/// Conformers supply only `historySnapshot` and, optionally, `persistAfterHistoryChange()`; the
/// shared defaults provide `canUndo`/`canRedo`/`recordUndo`/`undo`/`redo`.
@MainActor
protocol DiagramHistoryHosting: AnyObject {
    associatedtype Snapshot: Equatable & Sendable

    var history: DiagramHistoryManager<Snapshot> { get }

    /// The undoable state: reading captures the current state, writing applies a restored one.
    var historySnapshot: Snapshot { get set }

    /// Override to self-persist after `undo()`/`redo()` apply a restored snapshot.
    func persistAfterHistoryChange()
}

extension DiagramHistoryHosting {
    func persistAfterHistoryChange() {}

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Call at the start of every undoable action (and once, before positions change, at the start
    /// of a drag/resize gesture).
    func recordUndo(coalescingKey: AnyHashable? = nil) {
        history.checkpoint(historySnapshot, coalescingKey: coalescingKey)
    }

    func undo() {
        guard let previous = history.undo(current: historySnapshot) else { return }
        historySnapshot = previous
        persistAfterHistoryChange()
    }

    func redo() {
        guard let next = history.redo(current: historySnapshot) else { return }
        historySnapshot = next
        persistAfterHistoryChange()
    }
}
