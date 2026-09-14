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
        .position(x: participant.headerRect.midX, y: participant.headerRect.midY)
        .onTapGesture(count: 2) {
            viewModel.selectNode(participant.id, extending: false)
            sidebarTab = .inspector
            showSidebar = true
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
            .accessibilityLabel(messageAccessibilityLabel(message))
            .accessibilityAddTraits(.isButton)
            .onTapGesture(count: 2) {
                viewModel.clearSelection()
                viewModel.selectedMessageID = message.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                let newSelection = (viewModel.selectedMessageID == message.id) ? nil : message.id
                viewModel.clearSelection()
                viewModel.selectedMessageID = newSelection
            }
    }

    func messageAccessibilityLabel(_ message: SequenceLayoutModel.MessageLayout) -> String {
        "Message" + (message.label.map { ": \($0)" } ?? "")
    }
}
