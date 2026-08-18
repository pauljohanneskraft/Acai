import SwiftUI

/// Reports a node view's rendered size back through `NodeSizePreferenceKey`, keyed by node id,
/// so the view model can lay out edges and auto-size nodes. Applied to nodes that aren't
/// user-resized.
private struct MeasuredNodeModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: NodeSizePreferenceKey.self, value: [id: geo.size])
                }
            )
    }
}

extension View {
    func measuredNode(id: String) -> some View {
        modifier(MeasuredNodeModifier(id: id))
    }
}
