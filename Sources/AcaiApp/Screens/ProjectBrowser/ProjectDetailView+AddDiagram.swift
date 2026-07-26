import SwiftUI

/// Split out of `ProjectDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit — the "create a new freeform diagram" concern (unified empty-project state).
extension ProjectDetailView {
    /// Shown instead of the header's action buttons + two empty sections when a project has
    /// neither codebases nor diagrams yet — reuses `FreeformDiagramView.emptyCanvasHint`'s visual
    /// language and renders the same two actions the (now-hidden) header buttons would have, once,
    /// large, and centered.
    var emptyProjectContentState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.full")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Let's add your first codebase")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    addingCodebase = true
                } label: {
                    Label("Add codebase", systemImage: "plus")
                }
                .accessibilityIdentifier("projectDetail.addCodebaseButton")
                addDiagramButton
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    /// Offered wherever a new freeform diagram can be created: creates a blank canvas directly, no
    /// submenu or template choice. A prior revision offered one-tap starter templates ("Use Case",
    /// "Deployment") pre-populated with catalog node kinds; that quick-create shortcut was
    /// deliberately removed (see `BACKLOG.md`'s B26 entry) while keeping the underlying node kinds
    /// fully available for manual placement from the catalog.
    var addDiagramButton: some View {
        Button {
            createDiagram(name: "New Freeform Diagram")
        } label: {
            Label("Add Diagram", systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier("projectDetail.addDiagramButton")
    }

    func createDiagram(name: String) {
        if let id = model.freeforms.add(to: projectID, name: name) {
            model.selection = .freeformDiagram(id)
        }
    }
}
