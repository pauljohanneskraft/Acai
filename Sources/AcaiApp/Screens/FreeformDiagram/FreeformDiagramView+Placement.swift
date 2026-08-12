import SwiftUI

// MARK: - Point-and-Place Insertion

/// Ghost preview + cancel affordance + background-tap commit handling for
/// `FreeformDiagramViewModel.pendingPlacement`. Split from `FreeformDiagramView.swift` itself only to
/// stay under `type_body_length` — same rationale as `FreeformDiagramView+Canvas.swift`.
extension FreeformDiagramView {
    /// The canvas-space point under the currently tracked cursor/touch (`cursorLocation`), using the
    /// same screen→canvas transform as `handleCatalogDrop` — shared so point-and-place placement
    /// lands exactly where drag-drop would.
    var cursorCanvasPoint: CGPoint {
        CGPoint(
            x: (cursorLocation.x - canvasOffset.x) / canvasScale,
            y: (cursorLocation.y - canvasOffset.y) / canvasScale
        )
    }

    /// Background-tap handler: while a catalog placement is pending, commits it at the last tracked
    /// cursor/touch point instead of the default clear-selection behavior.
    func handleBackgroundTap() {
        guard !viewModel.commitPlacement(at: cursorCanvasPoint) else { return }
        viewModel.clearSelection()
    }

    /// On compact width (iPhone), `.inspector` collapses to a sheet covering nearly the whole
    /// screen — regular width (iPad/macOS) keeps its persistent side column instead, where the
    /// canvas stays visible and tappable alongside an open sidebar.
    var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// On compact width (iPhone), the Node Catalog sidebar is presented as a sheet with no dismiss
    /// chrome of its own (`FreeformDiagramView`'s `.inspector` isn't split into a
    /// compact-sheet-with-Done-button/regular-column pair the way `ClassDiagramView` is) and it
    /// covers nearly the whole canvas — so starting a placement there and leaving the sheet up
    /// would leave the user with a ghost preview and nothing tappable to commit it against.
    /// Closing the sidebar the moment placement begins keeps the point-and-place flow usable on
    /// iPhone without a redesign; regular width (iPad/macOS) is unaffected — the canvas stays
    /// visible next to the persistent sidebar column there, so repeatedly placing several nodes
    /// without reopening the sidebar each time still works.
    func beginningPlacementClosesCompactSidebar(_ pendingPlacement: FreeformDiagramNodeKind?) {
        guard pendingPlacement != nil, isCompactWidth else { return }
        showSidebar = false
    }

    /// A small label-and-icon preview of the pending catalog kind, following `cursorLocation` (the
    /// same live gesture-location tracking `canvasArea` already maintains for the context menu) —
    /// modeled on `InfiniteCanvas.selectionRectOverlay`'s "track a live gesture location" pattern.
    @ViewBuilder
    var placementGhostOverlay: some View {
        if let kind = viewModel.pendingPlacement {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                Text(kind.displayName)
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

    /// A floating HUD button to back out of placement mode without inserting — modeled on
    /// `InfiniteCanvas.zoomIndicator`'s floating, corner-anchored HUD pattern (fixed position, unlike
    /// the ghost preview, so it stays reachable regardless of where the cursor/touch currently is).
    @ViewBuilder
    var placementCancelButton: some View {
        if viewModel.pendingPlacement != nil {
            Button {
                viewModel.cancelPlacement()
            } label: {
                Label("Cancel Placement", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(.regularMaterial, in: Circle())
            .padding(10)
            .accessibilityIdentifier("freeform.cancelPlacementButton")
            .accessibilityLabel("Cancel Placement")
        }
    }
}
