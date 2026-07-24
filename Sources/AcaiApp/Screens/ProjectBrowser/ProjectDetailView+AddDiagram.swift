import SwiftUI

/// Split out of `ProjectDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit — this is the "create a new freeform diagram" concern (B26's template menu, B52's unified
/// empty-project state that offers the same actions).
extension ProjectDetailView {
    /// Shown instead of the header's action buttons + two empty sections when a project has
    /// neither codebases nor diagrams yet (B52) — reuses `FreeformDiagramView.emptyCanvasHint`'s
    /// visual language rather than inventing a new one, and renders the same two actions the
    /// (now-hidden) header buttons would have, once, large, and centered.
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
                addDiagramMenu
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    /// Offered wherever a new freeform diagram can be created: a blank canvas, or one of the
    /// starter templates (B26) pre-arranged with a handful of the catalog's own node kinds.
    var addDiagramMenu: some View {
        Menu {
            Button {
                createDiagram(name: "New Freeform Diagram", template: nil)
            } label: {
                Label("Blank Diagram", systemImage: "rectangle.dashed")
            }
            .accessibilityIdentifier("projectDetail.addDiagramButton.blank")
            Divider()
            ForEach(FreeformDiagramTemplate.allCases) { template in
                Button {
                    createDiagram(name: template.displayName, template: template)
                } label: {
                    Label(template.displayName, systemImage: template.systemImage)
                }
                .accessibilityIdentifier("projectDetail.addDiagramButton.template.\(template.id)")
            }
        } label: {
            Label("Add Diagram", systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier("projectDetail.addDiagramButton")
    }

    func createDiagram(name: String, template: FreeformDiagramTemplate?) {
        if let id = model.freeforms.add(to: projectID, name: name, template: template) {
            model.selection = .freeformDiagram(id)
        }
    }
}
