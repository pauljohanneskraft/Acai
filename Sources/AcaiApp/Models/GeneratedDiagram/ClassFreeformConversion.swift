import Foundation
import AcaiCore
import AcaiDiagram
import AcaiRender

/// Converts a class diagram (the default "Save as Freeform" path — every diagram type other than
/// Sequence/State/Package/Call Graph) into an editable freeform diagram: each type becomes a
/// `.type` node with full member/generic data, every relationship a matching edge, and (when the
/// diagram groups by directory/product) one `.package` container box per active group, sized to
/// enclose the members it contains.
struct ClassFreeformConversion: FreeformConversion {
    let context: FreeformConversionContext

    func items() -> [TypeDeclaration] {
        artifact.types
    }

    func sourceID(for item: TypeDeclaration) -> String {
        item.id
    }

    func defaultPosition(index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * 200 + 120, y: 120)
    }

    func makeNode(for item: TypeDeclaration, id: String, position: CGPoint) -> FreeformDiagram.Node {
        let showAnnotationStereotypes = diagram.classConfiguration?.showAnnotationStereotypes ?? true
        let languages = artifact.standardLanguageResolver
        let storedSize = diagram.nodeSizes[item.id]
        let stereotype = item.stereotype(
            annotationStereotypes: showAnnotationStereotypes
                ? languages.configuration(for: item).annotationStereotypes : [:]
        )
        return FreeformDiagram.Node(
            id: id,
            name: item.name,
            content: .type(.init(
                typeKind: item.kind,
                stereotype: stereotype,
                properties: item.members
                    .filter { $0.kind == .property || $0.kind == .subscript }
                    .map(freeformMember(from:)),
                methods: item.members
                    .filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }
                    .map(freeformMember(from:)),
                enumCases: item.enumCases.map { .init(name: $0.name) },
                genericParameters: item.genericParameters.map(\.name)
            )),
            positionX: Double(position.x),
            positionY: Double(position.y),
            width: storedSize?.width,
            height: storedSize?.height
        )
    }

    private func freeformMember(from member: Member) -> FreeformDiagram.Node.Member {
        .init(
            name: member.name,
            type: member.type?.name ?? "",
            accessLevel: member.accessLevel,
            isStatic: member.modifiers.contains(.static),
            isAbstract: member.modifiers.contains(.abstract)
        )
    }

    func makeEdges(idsBySourceID: [String: String]) -> [FreeformDiagram.Edge] {
        // `rel.source`/`rel.target` are already resolved to type ids by enrichment (falling back to
        // the bare name only for an unresolved/external endpoint); `idsBySourceID` holds only known
        // type ids, so the lookup below both maps to the freeform node and gates membership in one step.
        artifact.relationships.compactMap { rel in
            guard rel.source != rel.target,
                  let srcID = idsBySourceID[rel.source],
                  let tgtID = idsBySourceID[rel.target] else { return nil }
            return .init(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind)
        }
    }

    /// One `.package` freeform container node per active-grouping box (the same nested-prefix
    /// boxes `DiagramLayoutModel.groupingBoxes` draws behind the live Class Diagram), sized to
    /// enclose the already-converted member nodes it contains. `.none` produces nothing.
    ///
    /// Re-derives the box geometry here rather than calling `DiagramLayoutModel.groupingBoxes`
    /// directly: that type rebuilds its own nodes from `artifact` under the class diagram's
    /// filters, which can differ from what `makeNode` actually emitted above — recomputing from
    /// the emitted nodes keeps every box's members consistent with `memberNodes`.
    func groupingNodes(
        memberNodes: [FreeformDiagram.Node], idsBySourceID: [String: String]
    ) -> [FreeformDiagram.Node] {
        guard let grouping = diagram.classConfiguration?.grouping, grouping != .none else { return [] }
        let memberByNodeID = Dictionary(uniqueKeysWithValues: memberNodes.map { ($0.id, $0) })
        let byPrefix = groupingBoxPrefixes(
            grouping: grouping, memberByNodeID: memberByNodeID, idsBySourceID: idsBySourceID
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
                // still behind every member node (default `drawOrder` 0).
                drawOrder: value.depth - (maxDepth + 2)
            )
        }
    }

    /// One entry per path-prefix depth of every member's group key, merging member rects into their
    /// shared ancestor boxes — mirrors `DiagramLayoutModel.groupingBoxes`'s prefix-merge, but keyed
    /// against the freeform nodes already emitted above.
    private func groupingBoxPrefixes(
        grouping: ClassDiagramConfiguration.Grouping,
        memberByNodeID: [String: FreeformDiagram.Node],
        idsBySourceID: [String: String]
    ) -> [String: (label: String, depth: Int, rect: CGRect)] {
        let languages = artifact.standardLanguageResolver
        let configuration = diagram.classConfiguration ?? .init()

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
            guard let nodeID = idsBySourceID[type.id], let node = memberByNodeID[nodeID],
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
}
