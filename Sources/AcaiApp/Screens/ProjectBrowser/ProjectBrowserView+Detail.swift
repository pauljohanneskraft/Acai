import SwiftUI

extension ProjectBrowserView {
    @ViewBuilder
    func freeformDiagramDetail(diagramID: UUID) -> some View {
        if model.freeformDiagram(for: diagramID) != nil {
            FreeformDiagramView(diagramID: diagramID)
                .id(diagramID)
                .environmentObject(model)
        } else {
            Text(.app("View.ProjectBrowserView.DiagramNotFound"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var emptyState: some View {
        if model.store.projects.isEmpty {
            // The sidebar's own empty state carries the message and the New Project button.
            Color.clear
        } else {
            VStack(spacing: .spacingM) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(.app("View.ProjectBrowserView.SelectProjectDiagram"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
