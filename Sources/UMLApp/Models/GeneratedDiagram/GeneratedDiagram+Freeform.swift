import Foundation
import UMLCore
import UMLDiagram

extension GeneratedDiagram {

    func convertToFreeform(
        artifact: CodeArtifact,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> FreeformDiagram {
        if case .sequenceDiagram(let config) = content {
            return convertSequenceToFreeform(
                artifact: artifact, configuration: config,
                positions: positions, scale: scale, offset: offset
            )
        }
        if case .stateDiagram(let config) = content, let config {
            return convertStateToFreeform(
                artifact: artifact, configuration: config,
                positions: positions, scale: scale, offset: offset
            )
        }
        var ids: [String: String] = [:]

        let nodes = buildFreeformNodes(
            from: artifact,
            positions: positions,
            ids: &ids
        )
        let edges = buildFreeformEdges(from: artifact, ids: ids)

        return FreeformDiagram(
            name: name + " (Freeform)",
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    private func buildFreeformNodes(
        from artifact: CodeArtifact,
        positions: [String: CGPoint],
        ids: inout [String: String]
    ) -> [FreeformDiagram.Node] {
        var nodes: [FreeformDiagram.Node] = []

        for type in artifact.types {
            let nodeID = UUID().uuidString
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
                        .map { buildFreeformMember(from: $0) },
                    methods: type.members
                        .filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }
                        .map { buildFreeformMember(from: $0) },
                    enumCases: type.enumCases.map { .init(name: $0.name) },
                    genericParameters: type.genericParameters.map(\.name)
                )),
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        return nodes
    }

    private func buildFreeformMember(from member: Member) -> FreeformDiagram.Node.Member {
        .init(
            name: member.name,
            type: member.type?.name ?? "",
            accessLevel: member.accessLevel ?? .internal,
            isStatic: member.modifiers.contains(.static),
            isAbstract: member.modifiers.contains(.abstract)
        )
    }

    // MARK: - Sequence → Freeform

    /// Converts a sequence diagram into an editable freeform diagram: each participant becomes a
    /// lifeline node and every message (calls *and* returns) becomes a time-ordered message
    /// edge. The freeform editor renders these through the same sequence layout the generated
    /// view uses, so the converted diagram looks identical to its original while staying fully
    /// editable (move, relabel, reorder, add/remove).
    private func convertSequenceToFreeform(
        artifact: CodeArtifact,
        configuration: SequenceDiagramConfiguration,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> FreeformDiagram {
        let sequence = artifact.sequenceDiagram(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        )

        // One lifeline node per participant, at the exact x its lifeline had in the generated
        // view (the caller passes the live layout positions; the stride is only a fallback).
        var nodeIDByName: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, participant) in sequence.participants.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByName[participant.name] = nodeID
            let x = positions[participant.id]?.x ?? CGFloat(index) * 180 + 120
            nodes.append(FreeformDiagram.Node(
                id: nodeID,
                name: participant.name,
                content: .lifeline(participant.kind),
                positionX: Double(x),
                positionY: 100
            ))
        }

        let edges: [FreeformDiagram.Edge] = sequence.messages
            .sorted { $0.order < $1.order }
            .compactMap { message in
                guard let source = nodeIDByName[message.from],
                      let target = nodeIDByName[message.to] else { return nil }
                return FreeformDiagram.Edge(
                    sourceNodeID: source,
                    targetNodeID: target,
                    kind: .dependency,
                    label: message.label,
                    messageOrder: message.order,
                    messageKind: message.kind
                )
            }

        return FreeformDiagram(
            name: name + " (Freeform)",
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    // MARK: - State → Freeform

    /// Converts a state diagram into an editable freeform diagram: each state becomes a state
    /// node and every transition a labeled transition edge. The freeform editor renders these
    /// through the same `StateNodeView` the generated view uses, so the converted diagram
    /// looks identical to its original while staying fully editable.
    private func convertStateToFreeform(
        artifact: CodeArtifact,
        configuration: StateDiagramConfiguration,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> FreeformDiagram {
        // Analysis failures convert to an empty (but still editable) diagram.
        let state = (try? artifact.resolvingExtensions().stateDiagram(configuration: configuration))
            ?? StateDiagram()

        var nodeIDByStateID: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, diagramState) in state.states.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByStateID[diagramState.id] = nodeID
            let livePos = positions[diagramState.id]
            let storedPos = nodePositions[diagramState.id]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? CGFloat(index) * 160 + 120
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 100
            nodes.append(FreeformDiagram.Node(
                id: nodeID,
                name: diagramState.name,
                content: .state(diagramState.kind),
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        let edges: [FreeformDiagram.Edge] = state.transitions.compactMap { transition in
            guard let source = nodeIDByStateID[transition.from],
                  let target = nodeIDByStateID[transition.to] else { return nil }
            var edge = FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .association)
            edge.transition = .init(
                event: transition.event,
                guardCondition: transition.guardCondition,
                action: transition.action
            )
            return edge
        }

        return FreeformDiagram(
            name: name + " (Freeform)",
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    private func buildFreeformEdges(
        from artifact: CodeArtifact,
        ids: [String: String]
    ) -> [FreeformDiagram.Edge] {
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
