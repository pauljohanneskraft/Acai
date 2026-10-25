import SwiftUI

/// A sidebar row turned into a text field while it is being renamed: ⏎ commits, ⎋ reverts, and a
/// name left empty keeps the previous one rather than clearing it.
struct SidebarRenameField: View {
    @Binding var text: String
    let identifier: String
    let rename: (String) -> Void
    let finish: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(text: $text) {
            Text(.app("View.SidebarRenameField.Name"))
        }
        .textFieldStyle(.roundedBorder)
        .font(.callout)
        .focused($isFocused)
        .accessibilityIdentifier(identifier)
        .onAppear { isFocused = true }
        .onSubmit {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { rename(name) }
            finish()
        }
        .background {
            // Hidden button so Escape (macOS, external keyboard on iPad) backs out of the rename,
            // the way `FreeformDiagramView` backs out of placement.
            Button("") { finish() }
                .keyboardShortcut(.cancelRename)
                .hidden()
        }
    }
}

/// The one sidebar row being renamed, if any, and the name typed into it so far.
struct SidebarRename {
    private(set) var row: ProjectBrowserViewModel.Selection?
    var text = ""

    /// Seeded with the current name, so ⏎ on an untouched field is a no-op.
    mutating func begin(_ row: ProjectBrowserViewModel.Selection, currentName: String) {
        self.row = row
        text = currentName
    }

    mutating func finish() {
        row = nil
    }
}
