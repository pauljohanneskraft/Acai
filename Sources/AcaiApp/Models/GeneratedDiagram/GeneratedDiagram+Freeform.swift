import Foundation
import AcaiCore
import AcaiDiagram
import AcaiLibrary
import AcaiRender

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
        let groupingNodes = buildFreeformGroupingNodes(from: artifact, memberNodes: nodes, ids: ids)

        return FreeformDiagram(
            name: name + " (Freeform)",
            nodes: groupingNodes + nodes,
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
        let showAnnotationStereotypes = classConfiguration?.showAnnotationStereotypes ?? true
        let languages = artifact.standardLanguageResolver

        for (index, type) in artifact.types.enumerated() {
            // Distinct types can share an id when a language doesn't qualify by module (e.g. two
            // top-level Python classes of the same name in different files) — mirror the rendered
            // diagram's `removingDuplicates { $0.id }` first-wins rule so a later same-id
            // declaration maps onto the already-emitted node instead of creating a duplicate.
            guard ids[type.id] == nil else { continue }
            let nodeID = UUID().uuidString
            ids[type.id] = nodeID
            let livePos = positions[type.id]
            let storedPos = nodePositions[type.id]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? CGFloat(index) * 200 + 120
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 120
            let storedSize = nodeSizes[type.id]
            let stereotype = type.stereotype(
                annotationStereotypes: showAnnotationStereotypes
                    ? languages.configuration(for: type).annotationStereotypes : [:]
            )
            nodes.append(.init(
                id: nodeID,
                name: type.name,
                content: .type(.init(
                    typeKind: type.kind,
                    stereotype: stereotype,
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
                positionY: Double(y),
                width: storedSize?.width,
                height: storedSize?.height
            ))
        }

        return nodes
    }

    /// One `.package` freeform container node per active-grouping box (`ClassDiagramConfiguration
    /// .grouping`'s `.directory`/`.product` boxes, the same nested-prefix boxes
    /// `GroupingBoxLayer`/`DiagramLayoutModel.groupingBoxes` draw behind the live Class Diagram),
    /// sized to enclose the already-converted member nodes it contains. `.none` produces nothing.
    ///
    /// Deliberately re-derives the box geometry here (paralleling
    /// `DiagramLayoutModel.groupingBoxes`'s prefix-merge algorithm) rather than calling it directly:
    /// that type rebuilds its own `nodes` from `artifact` under the class diagram's access-level/
    /// generated-code/focus filters, which can be a *different* type set than `buildFreeformNodes`
    /// actually emitted above — recomputing from the emitted freeform nodes keeps every box's
    /// members consistent with what's really in `memberNodes`.
    private func buildFreeformGroupingNodes(
        from artifact: CodeArtifact,
        memberNodes: [FreeformDiagram.Node],
        ids: [String: String]
    ) -> [FreeformDiagram.Node] {
        guard let grouping = classConfiguration?.grouping, grouping != .none else { return [] }
        let memberByNodeID = Dictionary(uniqueKeysWithValues: memberNodes.map { ($0.id, $0) })
        let byPrefix = groupingBoxPrefixes(
            artifact: artifact, grouping: grouping, memberByNodeID: memberByNodeID, ids: ids
        )

        // Every box reserves a node-free strip at its top for its title tab; each ancestor level
        // adds one more tab-height — same constants `DiagramLayoutModel.groupingBoxes` uses, so a
        // converted diagram's boxes look the same size as the generated view's a moment before.
        let maxDepth = byPrefix.values.map(\.depth).max() ?? 1
        let titleStrip: CGFloat = 30
        let levelStep: CGFloat = 30
        return byPrefix.values.map { value in
            let inset = titleStrip + CGFloat(maxDepth - value.depth) * levelStep
            let rect = value.rect.insetBy(dx: -inset, dy: -inset)
            return FreeformDiagram.Node(
                name: value.label,
                content: .package,
                positionX: Double(rect.midX),
                positionY: Double(rect.midY),
                width: Double(rect.width),
                height: Double(rect.height),
                // Shallower (outer) boxes draw furthest back; deeper boxes draw closer to front but
                // still behind every member node, which stays at the default `drawOrder` of 0.
                drawOrder: value.depth - (maxDepth + 2)
            )
        }
    }

    /// One entry per path-prefix depth of every member's group key, merging member rects into their
    /// shared ancestor boxes — mirrors `DiagramLayoutModel.groupingBoxes`'s prefix-merge exactly, but
    /// keyed against the freeform nodes already emitted above (see `buildFreeformGroupingNodes`'s doc
    /// comment for why it isn't the same `nodes`/`positions` that type builds from `artifact` itself).
    private func groupingBoxPrefixes(
        artifact: CodeArtifact,
        grouping: ClassDiagramConfiguration.Grouping,
        memberByNodeID: [String: FreeformDiagram.Node],
        ids: [String: String]
    ) -> [String: (label: String, depth: Int, rect: CGRect)] {
        let languages = artifact.standardLanguageResolver
        let configuration = classConfiguration ?? .init()

        func groupKey(for type: TypeDeclaration) -> String? {
            let langConfig = languages.configuration(for: type)
            let diagramNode = GeneratedDiagramNode(
                from: type, configuration: configuration,
                annotationStereotypes: langConfig.annotationStereotypes,
                collectionTypeNames: langConfig.collectionTypeNames
            )
            switch grouping {
            case .none:
                return nil
            case .directory:
                return diagramNode.directoryPath
            case .product:
                return diagramNode.productGroup
            }
        }

        var byPrefix: [String: (label: String, depth: Int, rect: CGRect)] = [:]
        for type in artifact.types {
            guard let nodeID = ids[type.id], let node = memberByNodeID[nodeID],
                  let group = groupKey(for: type) else { continue }
            let size = CGSize(width: node.width ?? 200, height: node.height ?? 100)
            let rect = CGRect(
                x: node.positionX - size.width / 2, y: node.positionY - size.height / 2,
                width: size.width, height: size.height
            )
            let components = group.split(separator: "/").map(String.init)
            for depth in 1...max(components.count, 1) where !components.isEmpty {
                let key = components.prefix(depth).joined(separator: "/")
                if let existing = byPrefix[key] {
                    byPrefix[key] = (existing.label, existing.depth, existing.rect.union(rect))
                } else {
                    byPrefix[key] = (components[depth - 1], depth, rect)
                }
            }
        }
        return byPrefix
    }

    private func buildFreeformMember(from member: Member) -> FreeformDiagram.Node.Member {
        .init(
            name: member.name,
            type: member.type?.name ?? "",
            accessLevel: member.accessLevel,
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
        let sequence = SequenceDiagramBuilder(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        ).build(from: artifact)

        // One lifeline node per participant, at the exact x its lifeline had in the generated
        // view (the caller passes the live layout positions; the stride is only a fallback).
        // Keyed by participant *id* (what messages reference), not name: distinct participants can
        // share a name (a type and a free function), so a name-keyed map would merge them and drop
        // edges.
        var nodeIDByParticipantID: [String: String] = [:]
        var nodes: [FreeformDiagram.Node] = []
        for (index, participant) in sequence.participants.enumerated() {
            let nodeID = UUID().uuidString
            nodeIDByParticipantID[participant.id] = nodeID
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
                guard let source = nodeIDByParticipantID[message.from],
                      let target = nodeIDByParticipantID[message.to] else { return nil }
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
        let state = (try? StateDiagramBuilder(configuration: configuration).build(from: artifact.resolvingExtensions()))
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
        let package = PackageDiagramBuilder().build(
            from: artifact.enriched(using: artifact.standardLanguageResolver))

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
        let graph = CallGraphBuilder(scope: scope).build(from: artifact)

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
        // `rel.source`/`rel.target` are already resolved to type ids by enrichment (falling back to
        // the bare name only for an unresolved/external endpoint); `ids` holds only known type ids,
        // so the lookup below both maps to the freeform node and gates membership in one step.
        artifact.relationships.compactMap { rel in
            guard rel.source != rel.target,
                  let srcID = ids[rel.source],
                  let tgtID = ids[rel.target] else { return nil }
            return .init(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind)
        }
    }
}
