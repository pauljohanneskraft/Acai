import Foundation
import UMLCore
import UMLDiagram

extension GeneratedDiagram {

    func convertToCustom(
        artifact: CodeArtifact,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> CustomDiagram {
        if case .sequenceDiagram(let config) = content {
            return convertSequenceToCustom(
                artifact: artifact, configuration: config,
                positions: positions, scale: scale, offset: offset
            )
        }
        if case .stateDiagram(let config) = content, let config {
            return convertStateToCustom(
                artifact: artifact, configuration: config,
                positions: positions, scale: scale, offset: offset
            )
        }
        var ids: [String: String] = [:]

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
        ids: inout [String: String]
    ) -> [CustomDiagram.Node] {
        var nodes: [CustomDiagram.Node] = []

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

    // MARK: - Sequence → Custom

    /// Converts a sequence diagram into an editable custom diagram: each participant becomes a
    /// lifeline node and every message (calls *and* returns) becomes a time-ordered message
    /// edge. The custom editor renders these through the same sequence layout the generated
    /// view uses, so the converted diagram looks identical to its original while staying fully
    /// editable (move, relabel, reorder, add/remove).
    private func convertSequenceToCustom(
        artifact: CodeArtifact,
        configuration: SequenceDiagramConfiguration,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> CustomDiagram {
        let sequence = artifact.sequenceDiagram(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        )

        // One lifeline node per participant, at the exact x its lifeline had in the generated
        // view (the caller passes the live layout positions; the stride is only a fallback).
        var nodeIDByName: [String: String] = [:]
        var nodes: [CustomDiagram.Node] = []
        for (index, participant) in sequence.participants.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByName[participant.name] = nodeID
            let x = positions[participant.id]?.x ?? CGFloat(index) * 180 + 120
            nodes.append(CustomDiagram.Node(
                id: nodeID,
                name: participant.name,
                content: .lifeline(participant.kind),
                positionX: Double(x),
                positionY: 100
            ))
        }

        let edges: [CustomDiagram.Edge] = sequence.messages
            .sorted { $0.order < $1.order }
            .compactMap { message in
                guard let source = nodeIDByName[message.from],
                      let target = nodeIDByName[message.to] else { return nil }
                return CustomDiagram.Edge(
                    sourceNodeID: source,
                    targetNodeID: target,
                    kind: .dependency,
                    label: message.label,
                    messageOrder: message.order,
                    messageKind: message.kind
                )
            }

        return CustomDiagram(
            name: name + " (Custom)",
            diagramType: .sequenceDiagram,
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    // MARK: - State → Custom

    /// Converts a state diagram into an editable custom diagram: each state becomes a state
    /// node and every transition a labeled transition edge. The custom editor renders these
    /// through the same `StateNodeView` the generated view uses, so the converted diagram
    /// looks identical to its original while staying fully editable.
    private func convertStateToCustom(
        artifact: CodeArtifact,
        configuration: StateDiagramConfiguration,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> CustomDiagram {
        // Analysis failures convert to an empty (but still editable) diagram.
        let state = (try? artifact.resolvingExtensions().stateDiagram(configuration: configuration))
            ?? StateDiagram()

        var nodeIDByStateID: [String: String] = [:]
        var nodes: [CustomDiagram.Node] = []
        for (index, diagramState) in state.states.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByStateID[diagramState.id] = nodeID
            let livePos = positions[diagramState.id]
            let storedPos = nodePositions[diagramState.id]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? CGFloat(index) * 160 + 120
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 100
            nodes.append(CustomDiagram.Node(
                id: nodeID,
                name: diagramState.name,
                content: .state(diagramState.kind),
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        let edges: [CustomDiagram.Edge] = state.transitions.compactMap { transition in
            guard let source = nodeIDByStateID[transition.from],
                  let target = nodeIDByStateID[transition.to] else { return nil }
            var edge = CustomDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .association)
            edge.transition = .init(
                event: transition.event,
                guardCondition: transition.guardCondition,
                action: transition.action
            )
            return edge
        }

        return CustomDiagram(
            name: name + " (Custom)",
            diagramType: .stateDiagram,
            nodes: nodes,
            edges: edges,
            canvasScale: scale,
            canvasOffsetX: offset.x,
            canvasOffsetY: offset.y
        )
    }

    private func buildCustomEdges(
        from artifact: CodeArtifact,
        ids: [String: String]
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
