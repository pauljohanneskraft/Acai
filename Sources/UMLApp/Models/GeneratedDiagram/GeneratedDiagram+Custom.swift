import Foundation
import UMLCore

extension GeneratedDiagram {

    func convertToCustom(
        artifact: CodeArtifact,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> CustomDiagram {
        var ids: [String: UUID] = [:]

        let nodes = buildCustomNodes(
            from: artifact,
            positions: positions,
            ids: &ids
        )
        let edges = buildCustomEdges(from: artifact, ids: ids)

        return CustomDiagram(
            name: name + " (Custom)",
            diagramType: type,
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    private func buildCustomNodes(
        from artifact: CodeArtifact,
        positions: [String: CGPoint],
        ids: inout [String: UUID]
    ) -> [CustomDiagram.Node] {
        var nodes: [CustomDiagram.Node] = []

        for type in artifact.types {
            let nodeID = UUID()
            ids[type.name] = nodeID
            let livePos = positions[type.name]
            let storedPos = nodePositions[type.name]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? 0
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 0
            nodes.append(.init(
                id: nodeID,
                name: type.name,
                content: .type(.init(
                    typeKind: type.kind,
                    properties: type.members
                        .filter { $0.kind == .property || $0.kind == .subscript }
                        .map { buildCustomMember(from: $0) },
                    methods: type.members
                        .filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }
                        .map { buildCustomMember(from: $0) },
                    enumCases: type.enumCases.map { .init(name: $0.name) },
                    genericParameters: type.genericParameters.map(\.name)
                )),
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        return nodes
    }

    private func buildCustomMember(from member: Member) -> CustomDiagram.Node.Member {
        .init(
            name: member.name,
            type: member.type?.name ?? "",
            accessLevel: member.accessLevel ?? .internal,
            isStatic: member.modifiers.contains(.static),
            isAbstract: member.modifiers.contains(.abstract)
        )
    }

    private func buildCustomEdges(
        from artifact: CodeArtifact,
        ids: [String: UUID]
    ) -> [CustomDiagram.Edge] {
        let typeNames = Set(artifact.types.map(\.name))
        return artifact.relationships.compactMap { rel in
            guard typeNames.contains(rel.source),
                  typeNames.contains(rel.target),
                  rel.source != rel.target,
                  let srcID = ids[rel.source],
                  let tgtID = ids[rel.target] else { return nil }
            return .init(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind)
        }
    }
}
