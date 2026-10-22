import SwiftUI

/// Presents the New Project sheet, which `ProjectBrowserView` owns.
struct NewProjectAction {
    var isPresentingSheet: Bool
    var present: () -> Void
}

/// Published only while a project's detail is showing, which owns the Add Codebase sheet.
struct AddCodebaseAction {
    var isPresentingSheet: Bool
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

extension ProjectDetailView {
    var addCodebaseAction: AddCodebaseAction {
        AddCodebaseAction(isPresentingSheet: addingCodebase) { addingCodebase = true }
    }
}

/// Replaces `.newItem` because its automatic "New Window" holds ⌘N; `BrowserWindowCommands` re-adds it.
struct ProjectCommands: Commands {
    @FocusedValue(\.newProjectAction) private var newProject
    @FocusedValue(\.addCodebaseAction) private var addCodebase

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            ProjectCreationMenuButtons(newProject: newProject, addCodebase: addCodebase)
        }
    }
}

struct ProjectCreationMenuButtons: View {
    let newProject: NewProjectAction?
    let addCodebase: AddCodebaseAction?

    // A sheet presented over another is dropped and leaves its flag stuck, so both wait for it to close.
    private var isPresentingSheet: Bool {
        newProject?.isPresentingSheet == true || addCodebase?.isPresentingSheet == true
    }

    var body: some View {
        Button(.app("View.ProjectCommands.NewProject")) { newProject?.present() }
            .keyboardShortcut(.newProject)
            .disabled(newProject == nil || isPresentingSheet)
            .accessibilityIdentifier("menu.newProject")
        Button(.app("View.ProjectCommands.AddCodebase")) { addCodebase?.present() }
            .keyboardShortcut(.addCodebase)
            .disabled(addCodebase == nil || isPresentingSheet)
            .accessibilityIdentifier("menu.addCodebase")
    }
}
