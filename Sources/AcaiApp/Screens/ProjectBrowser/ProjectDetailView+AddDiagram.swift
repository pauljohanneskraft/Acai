import SwiftUI

extension ProjectDetailView {
    func isEmpty(_ project: Project) -> Bool {
        project.codebases.isEmpty && model.freeformDiagramsForProject(projectID).isEmpty
    }

    /// Shown instead of the header's action buttons + two empty sections when a project has
    /// neither codebases nor diagrams yet, reusing `FreeformDiagramView.emptyCanvasHint`'s visual
    /// language.
    var emptyProjectContentState: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "tray.full")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.ProjectDetailView.LetSAddFirst"))
                .font(.title3)
                .foregroundStyle(.secondary)
            // Bordered: inside iPhone's `List` row, a default-styled button makes the whole row its hit area.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.m) { emptyProjectActions }
                VStack(spacing: Spacing.m) { emptyProjectActions }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectDetail.emptyState")
    }

    @ViewBuilder
    private var emptyProjectActions: some View {
        Button {
            addingCodebase = true
        } label: {
            Label(.app("View.ProjectDetailView.AddCodebaseMenu"), systemImage: "plus")
        }
        .accessibilityIdentifier("projectDetail.addCodebaseButton")
        addDiagramButton
    }

    var addDiagramButton: some View {
        Button {
            createDiagram(name: "New Freeform Diagram")
        } label: {
            Label(.app("View.ProjectDetailView.AddDiagram"), systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier("projectDetail.addDiagramButton")
    }

    func createDiagram(name: String) {
        if let id = model.freeforms.add(to: projectID, name: name) {
            model.open(.freeformDiagram(id))
        }
    }
}
