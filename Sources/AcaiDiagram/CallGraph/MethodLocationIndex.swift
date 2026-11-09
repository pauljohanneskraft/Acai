import AcaiCore

/// Maps a `CallGraph.Node` id, as ``CallGraphNodeIdentity`` spells it, back to the `SourceLocation`
/// of the declaration it came from, so call-graph analyses can emit `file:line` jump targets that
/// the graph model itself doesn't carry. A value you instantiate over an artifact and query
/// (`MethodLocationIndex(artifact:).location(forNodeID:)`).
struct MethodLocationIndex: Sendable {
    private let locations: [String: SourceLocation]

    init(artifact: CodeArtifact) {
        var locations: [String: SourceLocation] = [:]
        let allTypes = artifact.flattened()
        let nodeIdentity = CallGraphNodeIdentity(types: allTypes)
        for type in allTypes {
            for member in type.members where member.isMethod {
                let key = nodeIdentity.nodeID(for: member, in: type)
                if locations[key] == nil, let location = member.location {
                    locations[key] = location
                }
            }
        }
        for function in artifact.freestandingFunctions {
            let key = nodeIdentity.nodeID(forFreeFunction: function)
            if locations[key] == nil, let location = function.location {
                locations[key] = location
            }
        }
        self.locations = locations
    }

    func location(forNodeID id: String) -> SourceLocation? { locations[id] }
}
