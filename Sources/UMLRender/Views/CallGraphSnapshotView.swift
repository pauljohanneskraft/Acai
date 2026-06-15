import SwiftUI
import UMLDiagram

/// A static rendering of a `CallGraph` from a pre-computed `CallGraphLayoutModel`: method boxes
/// (in-scope solid, out-of-scope callee leaves dashed and lighter) joined by call arrows whose
/// thickness encodes multiplicity. Used by the CLI image export (`uml image --call-graph`).
public struct CallGraphSnapshotView: View {
    let layout: CallGraphLayoutModel
    let padding: CGFloat

    public init(layout: CallGraphLayoutModel, padding: CGFloat = 40) {
        self.layout = layout
        self.padding = padding
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .dependency,
                        sourceRect: source,
                        targetRect: target,
                        lineWidthScale: min(1 + CGFloat(edge.weight - 1) * 0.35, 3)
                    )
                }
            }
            ForEach(layout.nodes) { node in
                methodBox(node)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
        .padding(padding)
        .background(Color.white)
    }

    private func methodBox(_ node: CallGraphLayoutModel.NodeFrame) -> some View {
        let method = node.node
        return Text(method.label)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Color(white: 0.1))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .frame(width: node.rect.width, height: node.rect.height)
            .background(method.inScope ? Color(red: 0.89, green: 0.95, blue: 0.99) : Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color(white: 0.5),
                        style: StrokeStyle(lineWidth: 1, dash: method.inScope ? [] : [4, 3])
                    )
            )
            .position(x: node.rect.midX, y: node.rect.midY)
    }
}
