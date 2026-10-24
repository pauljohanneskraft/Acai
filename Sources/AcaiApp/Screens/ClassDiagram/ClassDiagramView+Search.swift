import SwiftUI

extension ClassDiagramView {
    func showSearchBar() {
        // Focus is set by the search field's own onAppear, not here — the field doesn't exist in
        // the hierarchy yet on this line, so a focus request now would just be dropped.
        isSearchBarVisible = true
    }

    func selectChangedFileTypes(_ ids: Set<String>) {
        viewModel.selectedNodeIDs = ids
        sidebarTab = .inspector
        showSidebar = true
    }

    /// Applies a changed-file pick from the compare panel, which can arrive while this view is
    /// being recreated for a new comparison — hence also on appear.
    func applyChangedFileSelection() {
        guard let ids = changedFileSelection.wrappedValue else { return }
        changedFileSelection.wrappedValue = nil
        selectChangedFileTypes(ids)
    }

    /// Clears the query too, so a later ⌘F/toolbar tap starts fresh rather than reopening on a
    /// stale query with its dimming still applied for a frame.
    func hideSearchBar() {
        viewModel.dismissSearch()
        isSearchFieldFocused = false
        isSearchBarVisible = false
    }

    /// Pans (without changing zoom) so `nodeID`'s current position is centered — the "jump to
    /// match" behaviour, distinct from `centerDiagram()`'s fit-everything-to-view.
    func centerOnSearchMatch(_ nodeID: String?) {
        guard let nodeID, let position = viewModel.nodePosition(nodeID) else { return }
        withAnimation(Animation.canvasPan.respecting(reduceMotion: reduceMotion)) {
            canvasOffset = CGPoint(
                x: canvasViewportSize.width / 2 - position.x * canvasScale,
                y: canvasViewportSize.height / 2 - position.y * canvasScale
            )
        }
        // Held-down stepping walks matches faster than a file write completes, so the transform is
        // saved on the trailing edge of the burst instead of once per match.
        savePositions(debounced: true)
    }
}
