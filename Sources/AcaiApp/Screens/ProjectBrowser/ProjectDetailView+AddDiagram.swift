import SwiftUI

extension ProjectDetailView {
    func isEmpty(_ project: Project) -> Bool {
        project.codebases.isEmpty && model.freeformDiagramsForProject(projectID).isEmpty
    }

    /// Shown instead of the header's action buttons + two empty sections when a project has
    /// neither codebases nor diagrams yet, reusing `FreeformDiagramView.emptyCanvasHint`'s visual
    /// language.
    var emptyProjectContentState: some View {
        VStack(spacing: .spacingL) {
            Image(systemName: "tray.full")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.ProjectDetailView.LetSAddFirst"))
                .font(.title3)
                .foregroundStyle(.secondary)
            // Bordered: inside iPhone's `List` row, a default-styled button makes the whole row its hit area.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: .spacingM) { emptyProjectActions }
                VStack(spacing: .spacingM) { emptyProjectActions }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXXL)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectDetail.emptyState")
    }

    /// Regular width keeps the toolbar's Add Codebase/Add Diagram on screen beside this empty state,
    /// so these carry their own identifiers — two elements answering to one makes every query for it
    /// ambiguous, which throws rather than picking either.
    @ViewBuilder
    private var emptyProjectActions: some View {
        Button {
            addingCodebase = true
        } label: {
            Label(.app("View.ProjectDetailView.AddCodebaseMenu"), systemImage: "plus")
        }
        .accessibilityIdentifier("projectDetail.emptyState.addCodebaseButton")
        addDiagramButton(identifier: "projectDetail.emptyState.addDiagramButton")
    }

    func addDiagramButton(identifier: String = "projectDetail.addDiagramButton") -> some View {
        Button {
            createDiagram(name: "New Freeform Diagram")
        } label: {
            Label(.app("View.ProjectDetailView.AddDiagram"), systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier(identifier)
    }

    func createDiagram(name: String) {
        if let id = model.freeforms.add(to: projectID, name: name) {
            model.open(.freeformDiagram(id))
        }
    }
}
