import SwiftUI

/// Compact-width (iPhone) horizontal strip of catalog-kind icon buttons, shown above the bottom
/// bar while its "Place" segment is active (`FreeformDiagramView`). Tapping a kind enters
/// placement mode directly via `beginPlacement(kind:)`, bypassing the `.inspector` sidebar
/// entirely so the canvas stays visible and tappable the whole time — unlike the Node Catalog
/// sidebar, which collapses to a covering sheet at this width.
struct FreeformBottomToolbar: View {
    @ObservedObject var viewModel: FreeformDiagramViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FreeformDiagramNodeKind.allCases) { kind in
                    kindButton(kind)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background {
            // A solid background, not a translucent material: keeps this strip snapshot-testable
            // (`ImageRenderer` renders system materials as garbage pixels, not a thrown error).
            #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }

    private func kindButton(_ kind: FreeformDiagramNodeKind) -> some View {
        let isPending = viewModel.pendingPlacement == kind
        return Button {
            viewModel.beginPlacement(kind: kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.title3)
                Text(verbatim: kind.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 64)
            .foregroundStyle(isPending ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("freeform.bottomBar.placeButton.\(kind.id)")
    }
}
