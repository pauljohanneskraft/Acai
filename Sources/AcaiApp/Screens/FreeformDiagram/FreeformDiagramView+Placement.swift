import SwiftUI

// MARK: - Point-and-Place Insertion

/// Split from `FreeformDiagramView.swift` only to stay under `type_body_length`.
extension FreeformDiagramView {
    /// Uses the same screen→canvas transform as `handleCatalogDrop`, so point-and-place
    /// placement lands exactly where drag-drop would.
    var cursorCanvasPoint: CGPoint {
        CGPoint(
            x: (cursorLocation.x - canvasOffset.x) / canvasScale,
            y: (cursorLocation.y - canvasOffset.y) / canvasScale
        )
    }

    func handleBackgroundTap() {
        guard !viewModel.commitPlacement(at: cursorCanvasPoint) else { return }
        viewModel.clearSelection()
    }

    var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// On compact width, the Node Catalog sidebar is a sheet covering nearly the whole canvas
    /// with no dismiss chrome of its own — leaving it up during placement would leave the user
    /// with a ghost preview and nothing tappable to commit it against.
    func beginningPlacementClosesCompactSidebar(_ pendingPlacement: FreeformDiagramNodeKind?) {
        guard pendingPlacement != nil, isCompactWidth else { return }
        showSidebar = false
    }

    /// Follows the pointer — and on iPad the hovering Apple Pencil — drawn at canvas scale and centred
    /// where the node will land, so placement can be judged before the tap commits it.
    /// The labelled chip carries the accessibility identity; the shape is decorative. Lifelines and
    /// fragments lay out along the sequence layer rather than where they're dropped, so they get the
    /// chip alone.
    @ViewBuilder
    var placementGhostOverlay: some View {
        if let kind = viewModel.pendingPlacement, let node = viewModel.placementPreview {
            if node.content.canvasBehavior.rendersAsFreeNode {
                placementPreviewShape(node)
                    .scaleEffect(canvasScale)
                    .position(cursorLocation)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            placementChip(kind)
                .position(x: cursorLocation.x, y: cursorLocation.y + placementChipOffset(for: node))
                .allowsHitTesting(false)
                .accessibilityIdentifier("freeform.placementGhost")
        }
    }

    /// Below the previewed shape, or just above the point for a chip on its own.
    private func placementChipOffset(for node: FreeformDiagram.Node) -> CGFloat {
        guard node.content.canvasBehavior.rendersAsFreeNode else { return -32 }
        return viewModel.nodeSize(of: node).height * canvasScale / 2 + 24
    }

    @ViewBuilder
    private func placementPreviewShape(_ node: FreeformDiagram.Node) -> some View {
        if node.isResizable {
            let size = viewModel.nodeSize(of: node)
            FreeformNodeView(node: node, isSelected: false, size: size)
                .frame(width: size.width, height: size.height)
                .opacity(0.5)
        } else {
            FreeformNodeView(node: node, isSelected: false, size: nil)
                .fixedSize()
                .opacity(0.5)
        }
    }

    private func placementChip(_ kind: FreeformDiagramNodeKind) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: kind.systemImage)
            Text(verbatim: kind.displayName)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1))
        .opacity(0.9)
    }

    @ViewBuilder
    var placementCancelButton: some View {
        if viewModel.pendingPlacement != nil {
            Button {
                viewModel.cancelPlacement()
            } label: {
                Label(.app("View.FreeformDiagramView.CancelPlacement"), systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(Spacing.s)
            .background(.regularMaterial, in: Circle())
            .padding(Spacing.s)
            .accessibilityIdentifier("freeform.cancelPlacementButton")
            .accessibilityLabel(.app("View.FreeformDiagramView.CancelPlacement"))
        }
    }
}
