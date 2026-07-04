import UMLCore

/// Maps a `CallGraph.Node` id (`"Type.method"`, or `"function"` for a free function) back to the
/// `SourceLocation` of the declaration it came from, so call-graph analyses can emit `file:line` jump
/// targets that the graph model itself doesn't carry. A value you instantiate over an artifact and
/// query (`MethodLocationIndex(artifact:).location(forNodeID:)`).
struct MethodLocationIndex: Sendable {
    private let locations: [String: SourceLocation]

    init(artifact: CodeArtifact) {
        var locations: [String: SourceLocation] = [:]
        for type in artifact.flattened() {
            for member in type.members where member.isMethod {
                let key = "\(type.name).\(member.name)"
                if locations[key] == nil, let location = member.location {
                    locations[key] = location
                }
            }
        }
        for function in artifact.freestandingFunctions {
            if locations[function.name] == nil, let location = function.location {
                locations[function.name] = location
            }
        }
        self.locations = locations
    }

    func location(forNodeID id: String) -> SourceLocation? { locations[id] }
}
