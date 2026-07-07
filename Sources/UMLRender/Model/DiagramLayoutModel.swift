import CoreGraphics
import Foundation
import UMLCore

/// Pure, view-independent core of a generated class diagram: it turns a `CodeArtifact`
/// into laid-out nodes and edges. Shared by the macOS app's interactive view model and
/// the CLI's headless image renderer so both produce the same diagram from the same input.
///
/// It holds the built `nodes`/`edges` and exposes the layout, size-estimation and grouping
/// operations; callers own the mutable per-session state (measured sizes, user drags).
public struct DiagramLayoutModel: Sendable {

    /// A labelled box wrapping all nodes of one group (a directory level or a compiled
    /// product). `depth` is its nesting level (1 = outermost), used for z-order and inset.
    public struct GroupingBox: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let rect: CGRect
        public let depth: Int
    }

    public let nodes: [GeneratedDiagramNode]
    public let edges: [GeneratedDiagramEdge]
    public let configuration: ClassDiagramConfiguration

    /// Extra space baked into every node's layout footprint so neighbours never touch
    /// and small size-estimate errors can't produce visual overlap.
    public static let layoutMargin: CGFloat = 28

    /// Builds the nodes and edges for `artifact` under `configuration`: resolves extensions,
    /// optionally filters the source language's machine-generated types, hides types below the
    /// access floor, and keeps only the relationships enabled in the configuration.
    ///
    /// `language` is the source language's configuration, injected by the caller from the registry
    /// keyed on `artifact.metadata.sourceLanguage`; it supplies the generated-code filter and the
    /// annotation → stereotype map. The layout model never names a language itself.
    public init(
        artifact: CodeArtifact,
        configuration: ClassDiagramConfiguration,
        languages: LanguageConfigurationResolver
    ) {
        self.configuration = configuration

        var resolved = artifact.resolvingExtensions()
        if configuration.hideGeneratedTypes {
            resolved = resolved.filteringGeneratedTypes(using: languages)
        }

        // Single-class focus: prune to the subgraph around one type before any
        // visibility filtering, so access/relationship toggles apply to the focused set.
        if let focus = configuration.focus {
            let subset = FocusedSubsetBuilder(
                types: resolved.types, relationships: resolved.relationships, configuration: focus
            ).subset
            resolved.types = subset.types
            resolved.relationships = subset.relationships
        }

        let visibleTypes = resolved.types.filter {
            GeneratedDiagramNode.passesAccessFilter($0.accessLevel, minimum: configuration.minimumAccessLevel)
        }
        // Collapse nodes that share an id: distinct types can carry the same id when a language
        // doesn't qualify by module (e.g. two top-level Python classes of the same name in
        // different files). A diagram node set keyed by id must be unique — otherwise downstream
        // `Dictionary(uniqueKeysWithValues:)` layout maps trap. First declaration wins, matching
        // the view layer, which already renders `nodes.removingDuplicates { $0.id }`.
        self.nodes = visibleTypes.map { type in
            let config = languages.configuration(for: type)
            return GeneratedDiagramNode(
                from: type, configuration: configuration,
                annotationStereotypes: config.annotationStereotypes,
                collectionTypeNames: config.collectionTypeNames
            )
        }.removingDuplicates { $0.id }

        let typeIds = Set(visibleTypes.map(\.id))
        self.edges = Self.buildEdges(
            from: resolved.relationships,
            knownTypeIds: typeIds,
            configuration: configuration
        )
    }

    private static func buildEdges(
        from relationships: [Relationship],
        knownTypeIds: Set<String>,
        configuration: ClassDiagramConfiguration
    ) -> [GeneratedDiagramEdge] {
        guard configuration.showRelationships else { return [] }
        return relationships.compactMap { rel in
            guard knownTypeIds.contains(rel.source),
                  knownTypeIds.contains(rel.target),
                  rel.source != rel.target else { return nil }

            switch rel.kind {
            case .inheritance, .conformance:
                guard configuration.showInheritance else { return nil }
            case .composition, .aggregation:
                guard configuration.showComposition else { return nil }
            case .dependency:
                guard configuration.showDependency else { return nil }
            default:
                break
            }

            return GeneratedDiagramEdge(from: rel, showMultiplicities: configuration.showMultiplicities)
        }
    }

    // MARK: - Layout

    /// Runs the Sugiyama engine using the given *displayed* node sizes (user-resized >
    /// measured > estimated) inflated by a uniform margin, and returns node center positions.
    public func performLayout(sizes: [String: CGSize]) -> [String: CGPoint] {
        let engine = SugiyamaLayoutEngine()
        let margin = Self.layoutMargin
        let inputs = nodes.map { node -> SugiyamaLayoutEngine.NodeInput in
            let size = sizes[node.id] ?? CGSize(width: 200, height: 100)
            return SugiyamaLayoutEngine.NodeInput(
                id: node.id,
                size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2),
                group: groupKey(for: node)
            )
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.sourceID, targetID: $0.targetID, kind: $0.kind)
        }
        // Any grouping mode partitions the graph per group so each group box is a
        // contiguous, non-overlapping block; ungrouped uses the component-based layout.
        let result = configuration.grouping == .none
            ? engine.layout(nodes: inputs, edges: edgeInputs)
            : engine.layoutByGroup(nodes: inputs, edges: edgeInputs)
        return result.positions
    }

    /// The clustering key for a node under the active grouping mode.
    public func groupKey(for node: GeneratedDiagramNode) -> String? {
        switch configuration.grouping {
        case .none:
            return nil
        case .directory:
            return node.directoryPath
        case .product:
            return node.productGroup
        }
    }

    // MARK: - Grouping Boxes

    /// Nested bounding boxes for the active grouping mode, computed from the given node
    /// rects (center `positions` + `sizes`). One box per path prefix of every node's group
    /// key, giving multi-layer nesting. Empty when grouping is `.none`.
    public func groupingBoxes(
        positions: [String: CGPoint],
        sizes: [String: CGSize]
    ) -> [GroupingBox] {
        guard configuration.grouping != .none else { return [] }
        func nodeRect(_ id: String) -> CGRect? {
            guard let pos = positions[id] else { return nil }
            let size = sizes[id] ?? CGSize(width: 200, height: 100)
            return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                          width: size.width, height: size.height)
        }

        var byPrefix: [String: (label: String, depth: Int, rect: CGRect)] = [:]
        for node in nodes {
            guard let group = groupKey(for: node), let rect = nodeRect(node.id) else { continue }
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
        // Every box reserves a node-free strip at its top for its title tab; each ancestor
        // level adds one more tab-height. Draw shallower (outer) boxes first.
        let maxDepth = byPrefix.values.map(\.depth).max() ?? 1
        let titleStrip: CGFloat = 30
        let levelStep: CGFloat = 30
        return byPrefix
            .map { key, value in
                let inset = titleStrip + CGFloat(maxDepth - value.depth) * levelStep
                return GroupingBox(
                    id: key, label: value.label,
                    rect: value.rect.insetBy(dx: -inset, dy: -inset), depth: value.depth
                )
            }
            .sorted { $0.depth < $1.depth }
    }

    // MARK: - Size Estimation

    /// Heuristic intrinsic size for a node, used before (or without) live SwiftUI measurement —
    /// notably by the headless CLI renderer, where preference-key measurement never fires.
    public static func estimateSize(for node: GeneratedDiagramNode) -> CGSize {
        let lineHeight: CGFloat = 18
        let headerHeight: CGFloat = node.stereotype != nil ? 48 : 32

        let visibleProps = node.properties.count
        let visibleMethods = node.methods.count
        let visibleCases = node.enumCases.count

        let propHeight = CGFloat(max(visibleProps, 1)) * lineHeight
        let methodHeight = CGFloat(max(visibleMethods, 1)) * lineHeight
        let caseHeight = visibleCases == 0 ? 0 : CGFloat(visibleCases) * lineHeight
        let dividerCount: CGFloat = visibleCases == 0 ? 2 : 3
        let padding: CGFloat = 16

        let height = headerHeight + propHeight + methodHeight + caseHeight + (dividerCount * 1) + padding

        let allTexts = [node.name]
            + node.properties.map(\.displayText)
            + node.methods.map(\.displayText)
            + node.enumCases.map(\.displayText)
        let maxChars = allTexts.map(\.count).max() ?? 10
        let width = max(180, CGFloat(maxChars) * 7.5 + 28)

        return CGSize(width: min(width, 400), height: height)
    }
}
