import Foundation

extension FreeformDiagram {
    /// A named, timestamped snapshot of one freeform diagram's full node/edge state (B27).
    /// Deliberately not version control — no branching or diffing between checkpoints, just
    /// save/restore/delete of whole snapshots.
    struct Checkpoint: Identifiable, Codable, Hashable, Sendable {
        var id: UUID = UUID()
        var name: String
        var createdDate: Date = Date()
        var nodes: [Node]
        var edges: [Edge]
    }
}

extension FreeformDiagram {
    /// Appends a new checkpoint capturing the diagram's current nodes and edges.
    mutating func saveCheckpoint(named name: String) {
        checkpoints.append(Checkpoint(name: name, nodes: nodes, edges: edges))
    }

    /// Replaces the diagram's nodes and edges with those captured in the given checkpoint, if it
    /// still exists. The checkpoint itself is left in place, so it can be restored again later.
    mutating func restoreCheckpoint(_ id: Checkpoint.ID) {
        guard let checkpoint = checkpoints.first(where: { $0.id == id }) else { return }
        nodes = checkpoint.nodes
        edges = checkpoint.edges
    }

    mutating func deleteCheckpoint(_ id: Checkpoint.ID) {
        checkpoints.removeAll { $0.id == id }
    }
}
