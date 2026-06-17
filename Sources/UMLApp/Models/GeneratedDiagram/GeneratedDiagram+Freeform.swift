import Foundation
import UMLCore
import UMLDiagram
import UMLLibrary

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
        if case .packageDiagram = content {
            return convertPackageToFreeform(
                artifact: artifact, positions: positions, scale: scale, offset: offset
            )
        }
        if case .callGraph(let scope) = content {
            return convertCallGraphToFreeform(
                artifact: artifact, scope: scope, positions: positions, scale: scale, offset: offset
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

    // MARK: - Package → Freeform

    /// Converts a package diagram into an editable freeform diagram: each module becomes a UML
    /// `.package` node (the same shape the generated view shows) and every cross-module dependency
    /// a dependency edge. Coupling metrics aren't carried over — a hand-edited package diagram has
    /// no analysis behind it — so the freeform copy is the pure package/dependency structure.
    private func convertPackageToFreeform(
        artifact: CodeArtifact,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> FreeformDiagram {
        let package = artifact.enriched(configuration: artifact.standardLanguageConfiguration)
            .packageDependencyDiagram()

        var nodeIDByModuleID: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, module) in package.nodes.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByModuleID[module.id] = nodeID
            let livePos = positions[module.id]
            let storedPos = nodePositions[module.id]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? CGFloat(index) * 200 + 120
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 120
            nodes.append(FreeformDiagram.Node(
                id: nodeID,
                name: module.name,
                content: .package,
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        let edges: [FreeformDiagram.Edge] = package.edges.compactMap { edge in
            guard let source = nodeIDByModuleID[edge.from],
                  let target = nodeIDByModuleID[edge.to] else { return nil }
            return FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .dependency)
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

    // MARK: - Call Graph → Freeform

    /// Converts a static call graph into an editable freeform diagram: each method becomes a
    /// `.method` node (the same monospaced box the generated view shows) and every call a
    /// dependency edge. The scope's coverage/leaf distinction isn't carried over — a hand-edited
    /// call graph has no analysis behind it — so the freeform copy is the pure call structure.
    private func convertCallGraphToFreeform(
        artifact: CodeArtifact,
        scope: CallGraphScope,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) -> FreeformDiagram {
        let graph = artifact.callGraph(scope: scope)

        var nodeIDByGraphID: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, method) in graph.nodes.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByGraphID[method.id] = nodeID
            let livePos = positions[method.id]
            let storedPos = nodePositions[method.id]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? CGFloat(index) * 200 + 120
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 120
            nodes.append(FreeformDiagram.Node(
                id: nodeID,
                name: method.label,
                content: .method,
                positionX: Double(x),
                positionY: Double(y)
            ))
        }

        let edges: [FreeformDiagram.Edge] = graph.edges.compactMap { edge in
            guard let source = nodeIDByGraphID[edge.from],
                  let target = nodeIDByGraphID[edge.to] else { return nil }
            return FreeformDiagram.Edge(sourceNodeID: source, targetNodeID: target, kind: .dependency)
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
