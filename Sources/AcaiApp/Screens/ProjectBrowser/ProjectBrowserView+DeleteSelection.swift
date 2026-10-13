import SwiftUI

// macOS only: iPadOS does not deliver an unmodified ⌫ to a SwiftUI `keyboardShortcut`, so the
// sidebar's Delete is a Mac key. `KeyboardShortcutReference`'s sidebar group is macOS-only to match,
// which keeps the ⌘/ panel from listing a key an iPad keyboard never fires.
#if os(macOS)

/// A sidebar diagram row's pending deletion. Projects and codebases already have a confirmation of
/// their own (and their own `@State`); a diagram row has none, so deleting one by key needs this.
struct SidebarDiagramDeletion {
    enum Kind {
        case generated
        case freeform
    }

    let diagramID: UUID
    let name: String
    let kind: Kind
}

extension ProjectBrowserView {
    /// ⌫ on the selected sidebar row, as `KeyboardShortcutReference.deleteSidebarItem`. A hidden
    /// button is how this app binds a key an external keyboard sends (see `FreeformDiagramView`), and
    /// the only form the shortcut reference lists.
    var deleteSelectionShortcut: some View {
        Button("") { requestDeletionOfSelection() }
            .keyboardShortcut(.deleteSidebarItem)
            // Renaming a diagram puts a text field in the sidebar, where ⌫ edits the name.
            .disabled(renamingDiagramID != nil || !selectionIsDeletable)
            .hidden()
    }

    /// A repository entry, a findings or a query row stands for something the sidebar does not own,
    /// so Delete has nothing to act on there.
    private var selectionIsDeletable: Bool {
        switch model.selection {
        case .project, .codebase, .generatedDiagram, .freeformDiagram:
            true
        case .repository, .findings, .query, .none:
            false
        }
    }

    /// Always routes through a confirmation — the same one the row's context menu opens for a project
    /// or a codebase, and `SidebarDiagramDeletionConfirmation` for a diagram.
    private func requestDeletionOfSelection() {
        switch model.selection {
        case .project(let id):
            projectPendingDeletion = model.store.projects.first { $0.id == id }
        case .codebase(let id):
            codebasePendingDeletion = model.codebase(for: id)
        case .generatedDiagram(let id):
            diagramPendingDeletion = model.generatedDiagram(for: id)
                .map { SidebarDiagramDeletion(diagramID: $0.id, name: $0.name, kind: .generated) }
        case .freeformDiagram(let id):
            diagramPendingDeletion = model.freeformDiagram(for: id)
                .map { SidebarDiagramDeletion(diagramID: $0.id, name: $0.name, kind: .freeform) }
        case .repository, .findings, .query, .none:
            break
        }
    }
}

/// Deleting a diagram from its row is immediate (the row's own menu), but a key press is not a
/// two-step gesture, so the one ⌫ triggers asks first.
struct SidebarDiagramDeletionConfirmation: ViewModifier {
    @Binding var deletion: SidebarDiagramDeletion?
    @ObservedObject var model: ProjectBrowserViewModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            .app("View.ProjectBrowserView.ConfirmDeleteDiagram \(deletion?.name ?? "")"),
            isPresented: Binding(
                get: { deletion != nil },
                set: { if !$0 { deletion = nil } }
            ),
            presenting: deletion
        ) { pending in
            Button(.app("View.ProjectBrowserView.DeleteDiagram"), role: .destructive) {
                switch pending.kind {
                case .generated:
                    model.diagrams.remove(pending.diagramID)
                case .freeform:
                    model.freeforms.remove(pending.diagramID)
                }
            }
            .accessibilityIdentifier("sidebar.diagram.delete.confirmButton")
        } message: { _ in
            Text(.app("View.ProjectBrowserView.ThisCannotBeUndone"))
        }
    }
}
#endif
