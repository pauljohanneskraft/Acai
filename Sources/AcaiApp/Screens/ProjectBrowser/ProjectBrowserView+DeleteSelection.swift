import SwiftUI

// macOS only: iPadOS does not deliver an unmodified ⌫ to a SwiftUI `keyboardShortcut`.
#if os(macOS)

extension ProjectBrowserView {
    /// The only ⌫ binding for the sidebar; live only while the sidebar's `List` has focus.
    var deleteSelectionShortcut: some View {
        Button("") { requestSidebarDeletion() }
            .keyboardShortcut(.deleteSidebarItem)
            .disabled(sidebarDeleteAction == nil)
            .hidden()
    }

    /// Nil unless the focused sidebar holds a deletable selection that is not being renamed.
    var sidebarDeleteAction: SidebarDeleteAction? {
        guard sidebarIsFocused, renamingDiagramID == nil, let deletion = model.selectionDeletion else { return nil }
        return SidebarDeleteAction(deletion: deletion) { requestSidebarDeletion() }
    }

    private func requestSidebarDeletion() {
        switch model.selectionDeletion {
        case .project(let project):
            projectPendingDeletion = project
        case .codebase(let codebase):
            codebasePendingDeletion = codebase
        case .diagram(let diagram):
            diagramPendingDeletion = diagram
        case nil:
            break
        }
    }
}

struct SidebarDeleteAction {
    let deletion: SidebarDeletion
    let perform: () -> Void
}

private struct SidebarDeleteActionKey: FocusedValueKey {
    typealias Value = SidebarDeleteAction
}

extension FocusedValues {
    var sidebarDeleteAction: SidebarDeleteAction? {
        get { self[SidebarDeleteActionKey.self] }
        set { self[SidebarDeleteActionKey.self] = newValue }
    }
}

/// Edit ▸ Delete for the key window's focused sidebar selection; ⌫ itself is bound on the sidebar.
struct SidebarDeleteCommands: Commands {
    @FocusedValue(\.sidebarDeleteAction) private var action

    var body: some Commands {
        CommandGroup(after: .pasteboard) { SidebarDeleteMenuButton(action: action) }
    }
}

struct SidebarDeleteMenuButton: View {
    let action: SidebarDeleteAction?

    var body: some View {
        Button(title) { action?.perform() }
            .disabled(action == nil)
            .accessibilityIdentifier("menu.edit.deleteSidebarSelection")
    }

    private var title: LocalizedStringResource {
        switch action?.deletion {
        case .project:
            .app("View.SidebarDeleteCommands.DeleteProject")
        case .codebase:
            .app("View.SidebarDeleteCommands.DeleteCodebase")
        case .diagram:
            .app("View.SidebarDeleteCommands.DeleteDiagram")
        case nil:
            .app("View.SidebarDeleteCommands.Delete")
        }
    }
}

/// A diagram row's own Delete is immediate, but a key press is one step, so ⌫ asks first.
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
                model.delete(pending)
            }
            .accessibilityIdentifier("sidebar.diagram.delete.confirmButton")
        } message: { _ in
            Text(.app("View.ProjectBrowserView.ThisCannotBeUndone"))
        }
    }
}
#endif
