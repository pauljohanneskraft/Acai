import SwiftUI
import AcaiDiagram
import AcaiDiff
import AcaiRender

// Canvas content for `SequenceDiagramView`, kept in its own file only to stay under that file's
// own type-body-length limit — same pattern used for `SequenceDiagramSidebar+Inspector.swift`.
extension SequenceDiagramView {
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
                // `SequenceEnsembleView.messageColor` is `@Sendable`, and `viewModel` (a `@MainActor`
                // class) isn't, so this mirrors `ClassDiagramViewModel.exportPNGData`'s precomputed-
                // dictionary pattern for the same reason.
                let messageColors = Dictionary(uniqueKeysWithValues: layout.messages.compactMap { message in
                    viewModel.messageDeltaColor(message).map { (message.id, $0) }
                })
                ZStack(alignment: .topLeading) {
                    SequenceEnsembleView(layout: layout, messageColor: { messageColors[$0.id] })
                    ForEach(layout.participants) { participant in
                        participantHeader(participant)
                    }
                    ForEach(layout.messages) { message in
                        messageTapTarget(message)
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

    func participantHeader(_ participant: SequenceLayoutModel.ParticipantFrame) -> some View {
        SequenceParticipantHeader(
            participant: participant,
            isSelected: viewModel.selectedNodeIDs.contains(participant.id)
        )
        .frame(width: participant.headerRect.width, height: participant.headerRect.height)
        .deltaBadge(viewModel.participantDeltaStatus(participant.id))
        .diagramNodeAccessibility(
            DiagramElementDescription(
                participantNamed: participant.name, kind: participant.kind,
                delta: viewModel.participantDeltaStatus(participant.id)),
            identifier: "diagram.sequenceParticipant.\(participant.name)",
            isSelected: viewModel.selectedNodeIDs.contains(participant.id),
            onSelect: { viewModel.selectNode(participant.id, extending: false) },
            onShowDetails: { showDetails(forParticipant: participant.id) }
        )
        .position(x: participant.headerRect.midX, y: participant.headerRect.midY)
        .onTapGesture(count: 2) {
            showDetails(forParticipant: participant.id)
        }
        .diagramNodeInteraction(
            id: participant.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// An invisible tap strip over a message arrow, selecting it for the Inspector tab — mirrors
    /// `FreeformDiagramView+Canvas.swift`'s `messageTapTarget`, but sized to a full 44pt tall hit area
    /// (Freeform's 30pt strip is a tap-target shortfall this doesn't repeat).
    func messageTapTarget(_ message: SequenceLayoutModel.MessageLayout) -> some View {
        let width = max(abs(message.toX - message.fromX), 44)
        let midX = (message.fromX + message.toX) / 2
        let isSelected = viewModel.selectedMessageID == message.id
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
            .frame(width: width + 16, height: 44)
            .position(x: midX, y: message.y)
            .accessibilityElement()
            .accessibilityLabel(Text(.app("DiagramElementDescription.Message")))
            .accessibilityValue(Text(verbatim: messageDescription(message).summary))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggleMessageSelection(message.id) }
            .accessibilityAction(named: Text(.app("View.DiagramNodeAccessibility.ShowDetails"))) {
                showDetails(forMessage: message.id)
            }
            .onTapGesture(count: 2) {
                showDetails(forMessage: message.id)
            }
            .onTapGesture(count: 1) {
                toggleMessageSelection(message.id)
            }
    }

    private func messageDescription(_ layout: SequenceLayoutModel.MessageLayout) -> DiagramElementDescription {
        let messages = viewModel.orderedMessages
        guard messages.indices.contains(layout.id) else {
            return DiagramElementDescription(label: "", details: [])
        }
        let message = messages[layout.id]
        return DiagramElementDescription(
            edgeFrom: viewModel.participantName(message.from) ?? message.from,
            to: viewModel.participantName(message.to) ?? message.to,
            details: layout.label.map { [.app("DiagramElementDescription.EdgeLabel \($0)")] } ?? [],
            delta: viewModel.messageDeltaStatus(message))
    }

    private func toggleMessageSelection(_ id: Int) {
        let newSelection = (viewModel.selectedMessageID == id) ? nil : id
        viewModel.clearSelection()
        viewModel.selectedMessageID = newSelection
    }

    private func showDetails(forMessage id: Int) {
        viewModel.clearSelection()
        viewModel.selectedMessageID = id
        sidebarTab = .inspector
        showSidebar = true
    }

    private func showDetails(forParticipant id: String) {
        viewModel.selectNode(id, extending: false)
        sidebarTab = .inspector
        showSidebar = true
    }
}
