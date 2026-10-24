import SwiftUI
import AcaiDiagram
import AcaiDiff
import AcaiRender

// Canvas content for `StateDiagramView`, kept in its own file only to stay under that file's own
// type-body-length limit — same pattern used for `SequenceDiagramSidebar+Inspector.swift`.
extension StateDiagramView {
    // MARK: - Canvas

    var canvasContent: some View {
        let layout = viewModel.layout
        let rotors = rotorPlan(layout)
        return PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController,
            onViewportSizeChange: { canvasViewportSize = $0 },
            content: {
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
                        stateNode(node, rotors: rotors)
                    }
                    ForEach(layout.edges) { edge in
                        transitionTapTarget(edge, layout: layout, rotors: rotors)
                    }
                }
            }
        )
        .diagramRotors(rotors, in: rotorNamespace)
        // Overlay inside the canvas (not a sibling spanning the inspector column too), so it doesn't
        // render on top of the inspector when open — same as the other diagram types.
        .overlay(alignment: .topTrailing) {
            CompareOverlayButton(diagram: diagram, isPresented: isComparePresented)
        }
    }

    func rotorPlan(_ layout: StateLayoutModel) -> DiagramRotorPlan {
        DiagramRotorPlan(
            elements: layout.nodes.map { node in
                DiagramRotorPlan.Element(
                    id: node.id, label: node.state.name, delta: viewModel.stateDeltaStatus(node.id), frame: node.rect
                )
            },
            connections: layout.edges.compactMap { edge in
                guard let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) else {
                    return nil
                }
                return DiagramRotorPlan.Element(
                    connection: edge.accessibilityID, label: transitionDescription(edge).summary,
                    delta: transitionDelta(edge), from: source, to: target
                )
            }
        )
    }

    func stateNode(_ node: StateLayoutModel.NodeFrame, rotors: DiagramRotorPlan) -> some View {
        StateNodeView(
            state: node.state,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .deltaBadge(viewModel.stateDeltaStatus(node.id))
        .diagramNodeAccessibility(
            DiagramElementDescription(state: node.state, delta: viewModel.stateDeltaStatus(node.id)),
            identifier: "diagram.stateNode.\(node.state.name)",
            isSelected: viewModel.selectedNodeIDs.contains(node.id),
            onSelect: { viewModel.selectNode(node.id, extending: false) },
            onShowDetails: { showDetails(forState: node.id) }
        )
        .diagramRotorMember(id: node.id, in: rotors, namespace: rotorNamespace)
        .position(x: node.rect.midX, y: node.rect.midY)
        .onTapGesture(count: 2) {
            showDetails(forState: node.id)
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
    func transitionTapTarget(
        _ edge: StateLayoutModel.EdgeLayout, layout: StateLayoutModel, rotors: DiagramRotorPlan
    ) -> some View {
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
            .accessibilityValue(Text(verbatim: transitionDescription(edge).summary))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggleTransitionSelection(edge.id) }
            .accessibilityAction(named: Text(.app("View.DiagramNodeAccessibility.ShowDetails"))) {
                showDetails(forTransition: edge.id)
            }
            .diagramRotorMember(id: edge.accessibilityID, in: rotors, namespace: rotorNamespace)
            .onTapGesture(count: 2) {
                showDetails(forTransition: edge.id)
            }
            .onTapGesture(count: 1) {
                toggleTransitionSelection(edge.id)
            }
    }

    private func transitionDescription(_ edge: StateLayoutModel.EdgeLayout) -> DiagramElementDescription {
        DiagramElementDescription(
            edgeFrom: viewModel.stateName(edge.from) ?? edge.from,
            to: viewModel.stateName(edge.to) ?? edge.to,
            details: [],
            delta: transitionDelta(edge))
    }

    private func transitionDelta(_ edge: StateLayoutModel.EdgeLayout) -> DeltaStatus? {
        let transitions = viewModel.diagram?.transitions ?? []
        return transitions.indices.contains(edge.id) ? viewModel.transitionDeltaStatus(transitions[edge.id]) : nil
    }

    private func toggleTransitionSelection(_ id: Int) {
        let newSelection: Int? = (viewModel.selectedTransitionID == id) ? nil : id
        viewModel.clearSelection()
        viewModel.selectedTransitionID = newSelection
    }

    private func showDetails(forTransition id: Int) {
        viewModel.clearSelection()
        viewModel.selectedTransitionID = id
        sidebarTab = .inspector
        showSidebar = true
    }

    private func showDetails(forState id: String) {
        viewModel.selectNode(id, extending: false)
        sidebarTab = .inspector
        showSidebar = true
    }
}

extension StateLayoutModel.EdgeLayout {
    fileprivate var accessibilityID: String {
        "diagram.stateTransition.\(id)"
    }
}
