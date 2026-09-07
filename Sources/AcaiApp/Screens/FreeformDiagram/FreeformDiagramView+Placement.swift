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

    @ViewBuilder
    var placementGhostOverlay: some View {
        if let kind = viewModel.pendingPlacement {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                Text(verbatim: kind.displayName)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1))
            .opacity(0.9)
            .position(x: cursorLocation.x, y: cursorLocation.y - 32)
            .allowsHitTesting(false)
            .accessibilityIdentifier("freeform.placementGhost")
        }
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
            .padding(8)
            .background(.regularMaterial, in: Circle())
            .padding(10)
            .accessibilityIdentifier("freeform.cancelPlacementButton")
            .accessibilityLabel(.app("View.FreeformDiagramView.CancelPlacement"))
        }
    }
}
