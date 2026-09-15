import SwiftUI
import AcaiDiagram
import AcaiDiff
import AcaiRender

// Canvas content for `StateDiagramView`, kept in its own file only to stay under that file's own
// type-body-length limit — same pattern used for `SequenceDiagramSidebar+Inspector.swift`.
extension StateDiagramView {
    // MARK: - Canvas

    var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController,
            onViewportSizeChange: { canvasViewportSize = $0 },
            content: {
                let layout = viewModel.layout
                // A plain Sendable dictionary, not a closure capturing `viewModel` directly —
                // `StateEnsembleView.edgeColor` is `@Sendable`, and `viewModel` (a `@MainActor`
                // class) isn't, so this mirrors `ClassDiagramViewModel.exportPNGData`'s precomputed-
                // dictionary pattern for the same reason.
                let edgeColors = Dictionary(uniqueKeysWithValues: layout.edges.compactMap { edge in
                    viewModel.transitionDeltaColor(edge).map { (edge.id, $0) }
                })
                ZStack(alignment: .topLeading) {
                    StateEnsembleView(layout: layout, edgeColor: { edgeColors[$0.id] })
                    ForEach(layout.nodes) { node in
                        stateNode(node)
                    }
                    ForEach(layout.edges) { edge in
                        transitionTapTarget(edge, layout: layout)
                    }
                }
            }
        )
        // Overlay inside the canvas (not a sibling spanning the inspector column too), so it doesn't
        // render on top of the inspector when open — same as the other diagram types.
        .overlay(alignment: .topTrailing) {
            CompareOverlayButton(diagram: diagram, isPresented: isComparePresented)
        }
    }

    func stateNode(_ node: StateLayoutModel.NodeFrame) -> some View {
        StateNodeView(
            state: node.state,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .deltaBadge(viewModel.stateDeltaStatus(node.id))
        .position(x: node.rect.midX, y: node.rect.midY)
        .onTapGesture(count: 2) {
            viewModel.selectNode(node.id, extending: false)
            sidebarTab = .inspector
            showSidebar = true
        }
        .diagramNodeInteraction(
            id: node.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// An invisible tap strip over a transition arrow, selecting it for the Inspector tab —
    /// same rationale as `SequenceDiagramView.messageTapTarget`, sized to a full 44pt hit area.
    func transitionTapTarget(_ edge: StateLayoutModel.EdgeLayout, layout: StateLayoutModel) -> some View {
        let midpoint: CGPoint = {
            guard let from = layout.frame(for: edge.from), let to = layout.frame(for: edge.to) else {
                return .zero
            }
            return CGPoint(x: (from.midX + to.midX) / 2, y: (from.midY + to.midY) / 2)
        }()
        let isSelected = viewModel.selectedTransitionID == edge.id
        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .cursorOnHover(.pointingHand)
            #endif
            .frame(width: 44, height: 44)
            .position(midpoint)
            .accessibilityElement()
            .accessibilityLabel(
                edge.label.map { Text(.app("View.StateDiagramView.TransitionLabel \($0)")) }
                    ?? Text(.app("View.StateDiagramView.Transition"))
            )
            .accessibilityAddTraits(.isButton)
            .onTapGesture(count: 2) {
                viewModel.clearSelection()
                viewModel.selectedTransitionID = edge.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                let newSelection: Int? = (viewModel.selectedTransitionID == edge.id) ? nil : edge.id
                viewModel.clearSelection()
                viewModel.selectedTransitionID = newSelection
            }
    }
}
