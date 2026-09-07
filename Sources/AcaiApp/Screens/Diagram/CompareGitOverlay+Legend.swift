import SwiftUI
import AcaiDiagram
import AcaiRender

extension CompareGitPanel {
    /// Colour key for the delta edges, shown under the changed-files list. The colours come from
    /// `DeltaEdgeColors.standard`, the same source the rendered diagram uses.
    var legend: some View {
        HStack(spacing: 10) {
            swatch(Color(hex: DeltaEdgeColors.standard.added), .app("View.CompareGitOverlay.Added"))
            swatch(Color(hex: DeltaEdgeColors.standard.removed), .app("View.CompareGitOverlay.Removed"))
            swatch(Color(hex: DeltaEdgeColors.standard.changed), .app("View.CompareGitOverlay.Changed"))
        }
    }

    private func swatch(_ color: Color, _ label: LocalizedStringResource) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(localized: label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
