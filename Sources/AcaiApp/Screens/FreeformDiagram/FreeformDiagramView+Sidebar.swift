import SwiftUI

// MARK: - Sidebar (Catalog + Inspector)

/// Split from `FreeformDiagramView.swift` only to stay under `type_body_length`.
extension FreeformDiagramView {
    var sidebarContent: some View {
        VStack(spacing: .zero) {
            Picker("", selection: $sidebarTab) {
                Text(.app("View.FreeformDiagramView.Catalog")).tag(SidebarTab.catalog)
                Text(.app("View.FreeformDiagramView.Inspector")).tag(SidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(Spacing.s)

            Divider()

            switch sidebarTab {
            case .catalog:
                FreeformDiagramCatalog(viewModel: viewModel)
            case .inspector:
                FreeformDiagramInspector(
                    viewModel: viewModel,
                    isEditingText: $isEditingText,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
        }
        .background {
            #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }
}
