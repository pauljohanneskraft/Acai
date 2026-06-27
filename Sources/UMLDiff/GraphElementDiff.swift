/// The node/edge delta shared by the id-node + `(from,to)`-edge diagram diffs (package, call
/// graph). Construct it with both revisions' node ids and weighted edges, then ask it for each
/// element's status. A node is added/removed by id-set difference; a weighted edge is *changed*
/// when its weight moved.
struct GraphElementDiff: Sendable {
    /// A directed edge's identity for diffing.
    struct EdgeKey: Hashable, Sendable {
        let from: String
        let to: String
    }

    private let nodeStatus: [String: DeltaStatus]
    private let edgeStatus: [EdgeKey: DeltaStatus]

    init(oldNodeIDs: [String], newNodeIDs: [String], oldEdges: [EdgeKey: Int], newEdges: [EdgeKey: Int]) {
        let oldNodes = Set(oldNodeIDs), newNodes = Set(newNodeIDs)
        var nodeStatus: [String: DeltaStatus] = [:]
        for id in newNodes { nodeStatus[id] = oldNodes.contains(id) ? .unchanged : .added }
        for id in oldNodes where !newNodes.contains(id) { nodeStatus[id] = .removed }
        self.nodeStatus = nodeStatus

        var edgeStatus: [EdgeKey: DeltaStatus] = [:]
        for (key, weight) in newEdges {
            edgeStatus[key] = oldEdges[key].map { $0 == weight ? .unchanged : .changed } ?? .added
        }
        for key in oldEdges.keys where newEdges[key] == nil { edgeStatus[key] = .removed }
        self.edgeStatus = edgeStatus
    }

    func status(ofNode id: String) -> DeltaStatus { nodeStatus[id] ?? .unchanged }
    func status(of edge: EdgeKey) -> DeltaStatus { edgeStatus[edge] ?? .unchanged }
}
