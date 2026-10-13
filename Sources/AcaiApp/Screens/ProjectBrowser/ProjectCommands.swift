import SwiftUI

/// Presents the New Project sheet, which `ProjectBrowserView` owns.
struct NewProjectAction {
    var present: () -> Void
}

/// Presents the Add Codebase sheet for the project on screen, which `ProjectDetailView` owns — so the
/// menu item is enabled exactly while a project's detail is showing.
struct AddCodebaseAction {
    var present: () -> Void
}

private struct NewProjectActionKey: FocusedValueKey {
    typealias Value = NewProjectAction
}

private struct AddCodebaseActionKey: FocusedValueKey {
    typealias Value = AddCodebaseAction
}

extension FocusedValues {
    var newProjectAction: NewProjectAction? {
        get { self[NewProjectActionKey.self] }
        set { self[NewProjectActionKey.self] = newValue }
    }

    var addCodebaseAction: AddCodebaseAction? {
        get { self[AddCodebaseActionKey.self] }
        set { self[AddCodebaseActionKey.self] = newValue }
    }
}

/// The two creation actions, in the File menu. `replacing:` rather than `after:` because the group's
/// own "New Window" item already holds ⌘N, and of two items sharing a shortcut macOS fires only the
/// first — "Open in New Window" stays, since `BrowserWindowCommands` appends it after this group.
struct ProjectCommands: Commands {
    @FocusedValue(\.newProjectAction) private var newProject
    @FocusedValue(\.addCodebaseAction) private var addCodebase

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            ProjectCreationMenuButtons(newProject: newProject, addCodebase: addCodebase)
        }
    }
}

/// Takes the actions as plain values: a `Commands` struct's own property wrappers are not in scope for
/// the buttons' actions, which is why `QuickOpenMenuButton` does the same.
struct ProjectCreationMenuButtons: View {
    let newProject: NewProjectAction?
    let addCodebase: AddCodebaseAction?

    var body: some View {
        Button(.app("View.ProjectCommands.NewProject")) { newProject?.present() }
            .keyboardShortcut(.newProject)
            .disabled(newProject == nil)
        Button(.app("View.ProjectCommands.AddCodebase")) { addCodebase?.present() }
            .keyboardShortcut(.addCodebase)
            .disabled(addCodebase == nil)
    }
}
