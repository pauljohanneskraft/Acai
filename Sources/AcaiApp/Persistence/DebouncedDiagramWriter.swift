import Foundation

/// Encodes one generated diagram to its own file. A protocol so a test can count writes instead of
/// inferring them from file contents, which can't tell one write from three.
protocol GeneratedDiagramWriting: Sendable {
    func write(_ diagram: GeneratedDiagram, to url: URL) throws
}

struct JSONGeneratedDiagramWriter: GeneratedDiagramWriting {
    func write(_ diagram: GeneratedDiagram, to url: URL) throws {
        try JSONEncoder().encode(diagram).write(to: url, options: .atomic)
    }
}

/// Persists generated diagrams, coalescing a burst of saves for the same diagram into a single
/// trailing-edge write performed off the main actor.
///
/// Stepping through search matches recentres the canvas on every match, so the canvas transform is
/// saved as fast as the user can hold a key down — each save a synchronous JSON encode plus an
/// atomic file write, which on a large diagram is enough to stutter the pan animation.
@MainActor
final class DebouncedDiagramWriter {
    private let debounce: Duration
    private let writer: any GeneratedDiagramWriting
    private var pending: [UUID: Task<Void, Never>] = [:]

    init(debounce: Duration = .milliseconds(400), writer: any GeneratedDiagramWriting = JSONGeneratedDiagramWriter()) {
        self.debounce = debounce
        self.writer = writer
    }

    /// Writes on the spot, dropping any pending debounced write for the same diagram so an older
    /// snapshot can't land on top of this one.
    func writeNow(_ diagram: GeneratedDiagram, to url: URL) throws {
        pending[diagram.id]?.cancel()
        try writer.write(diagram, to: url)
    }

    /// Schedules a trailing-edge write. `latest` is read when the timer fires rather than captured
    /// now, so whatever the burst ended on is what reaches disk.
    func schedule(
        _ diagramID: UUID,
        to url: URL,
        latest: @escaping @MainActor () -> GeneratedDiagram?,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) {
        pending[diagramID]?.cancel()
        pending[diagramID] = Task { [debounce, writer] in
            guard (try? await Task.sleep(for: debounce)) != nil, let diagram = latest() else { return }
            do {
                try await Task.detached(priority: .utility) { try writer.write(diagram, to: url) }.value
            } catch {
                onFailure(error)
            }
        }
    }

    /// Drops a scheduled write without performing it — for a diagram about to be deleted, whose file
    /// must not be written again after removal.
    func cancel(_ diagramID: UUID) {
        pending.removeValue(forKey: diagramID)?.cancel()
    }

    /// Awaits every scheduled write, so a caller that needs "saved" to have actually happened (a
    /// scene going away, a test observing the trailing write) doesn't have to guess at the timing.
    func flush() async {
        let scheduled = Array(pending.values)
        pending.removeAll()
        for write in scheduled {
            await write.value
        }
    }
}
