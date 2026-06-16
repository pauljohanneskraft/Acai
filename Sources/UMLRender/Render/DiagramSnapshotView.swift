import SwiftUI
import UMLCore

/// A static, non-interactive rendering of a generated class diagram, used to produce image
/// exports. It composes the same `GroupingBoxView` / `TypeNodeView` / `RelationshipEdgeView`
/// the live canvas uses — but without gestures, selection, zoom or the infinite canvas — so
/// snapshots match what the app shows.
///
/// All coordinates are expected pre-normalized to the content's own space (top-left at the
/// origin); the view sizes itself to `contentSize` plus a uniform `padding`.
public struct DiagramSnapshotView: View {
    let nodes: [GeneratedDiagramNode]
    let edges: [GeneratedDiagramEdge]
    /// Node center positions, normalized so the content's top-left sits at the origin.
    let positions: [String: CGPoint]
    let sizes: [String: CGSize]
    let groupingBoxes: [DiagramLayoutModel.GroupingBox]
    let contentSize: CGSize
    let padding: CGFloat
    let palette: DiagramPalette

    public init(
        nodes: [GeneratedDiagramNode],
        edges: [GeneratedDiagramEdge],
        positions: [String: CGPoint],
        sizes: [String: CGSize],
        groupingBoxes: [DiagramLayoutModel.GroupingBox],
        contentSize: CGSize,
        padding: CGFloat,
        palette: DiagramPalette = .light
    ) {
        self.nodes = nodes
        self.edges = edges
        self.positions = positions
        self.sizes = sizes
        self.groupingBoxes = groupingBoxes
        self.contentSize = contentSize
        self.padding = padding
        self.palette = palette
    }

    private func size(for id: String) -> CGSize {
        sizes[id] ?? CGSize(width: 200, height: 100)
    }

    private func rect(for id: String) -> CGRect? {
        guard let pos = positions[id] else { return nil }
        let size = size(for: id)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    public var body: some View {
        ZStack {
            // Grouping boxes sit behind everything.
            ForEach(groupingBoxes) { box in
                GroupingBoxView(label: box.label)
                    .frame(width: box.rect.width, height: box.rect.height)
                    .position(x: box.rect.midX, y: box.rect.midY)
            }

            // Relationship edges.
            ForEach(edges.removingDuplicates(by: \.id)) { edge in
                if let sourceRect = rect(for: edge.sourceID),
                   let targetRect = rect(for: edge.targetID) {
                    RelationshipEdgeView(
                        kind: edge.kind, sourceRect: sourceRect, targetRect: targetRect,
                        sourceLabel: edge.sourceLabel, targetLabel: edge.targetLabel
                    )
                }
            }

            // Type nodes on top.
            ForEach(nodes.removingDuplicates(by: \.id)) { node in
                if let pos = positions[node.id] {
                    let size = size(for: node.id)
                    TypeNodeView(node: node, isSelected: false)
                        .frame(width: size.width, height: size.height)
                        .position(pos)
                }
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }
}
