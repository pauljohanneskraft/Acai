import Foundation

extension FreeformDiagram {
    /// A named, timestamped snapshot of one freeform diagram's full node/edge state. Deliberately
    /// not version control — no branching or diffing, just save/restore/delete of whole snapshots.
    struct Checkpoint: Identifiable, Codable, Hashable, Sendable {
        var id: UUID = UUID()
        var name: String
        var createdDate: Date = Date()
        var nodes: [Node]
        var edges: [Edge]
    }
}

extension FreeformDiagram {
    mutating func saveCheckpoint(named name: String) {
        checkpoints.append(Checkpoint(name: name, nodes: nodes, edges: edges))
    }

    mutating func restoreCheckpoint(_ id: Checkpoint.ID) {
        guard let checkpoint = checkpoints.first(where: { $0.id == id }) else { return }
        nodes = checkpoint.nodes
        edges = checkpoint.edges
    }

    mutating func deleteCheckpoint(_ id: Checkpoint.ID) {
        checkpoints.removeAll { $0.id == id }
    }
}
