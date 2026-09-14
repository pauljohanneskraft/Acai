import CoreGraphics

/// The union of everything an export needs to fit: every container/regular node's rect, plus
/// (when the diagram has sequence content) every lifeline header, combined-fragment frame, and a
/// margin for a self-loop message hanging off the right-most lifeline.
struct FreeformDiagramContentBounds {
    let nodes: [FreeformDiagram.Node]
    let sizes: [String: CGSize]
    let sequenceLayout: SequenceLayoutModel?
    let sequenceAnchorY: CGFloat

    var rect: CGRect {
        var rects: [CGRect] = nodes.compactMap { node in
            guard node.content.canvasBehavior.rendersAsFreeNode || node.isResizable else {
                // Lifelines/fragments render through the sequence layer, accounted for below.
                return nil
            }
            let size = sizes[node.id] ?? CGSize(width: 120, height: 60)
            return CGRect(
                x: node.positionX - size.width / 2, y: node.positionY - size.height / 2,
                width: size.width, height: size.height)
        }

        if let sequenceLayout {
            let headerRects = sequenceLayout.participants.map { $0.headerRect.offsetBy(dx: 0, dy: sequenceAnchorY) }
            let fragmentRects = sequenceLayout.fragments.map { $0.rect.offsetBy(dx: 0, dy: sequenceAnchorY) }
            rects.append(contentsOf: headerRects)
            rects.append(contentsOf: fragmentRects)
            let maxHeaderX = sequenceLayout.participants.map(\.headerRect.maxX).max() ?? 0
            rects.append(CGRect(
                x: maxHeaderX, y: sequenceAnchorY,
                width: SequenceLayoutModel.selfLoopWidth, height: sequenceLayout.contentSize.height))
        }

        guard let first = rects.first else {
            return CGRect(x: 0, y: 0, width: 200, height: 120)
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}
