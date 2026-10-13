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
        .onCancelKey(finish)
    }
}

private extension View {
    /// ⎋ while the field is up. macOS routes Escape through `onExitCommand`, which iOS doesn't have
    /// — there a hardware keyboard's Escape arrives as a key press instead.
    @ViewBuilder
    func onCancelKey(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        onKeyPress(.escape) {
            action()
            return .handled
        }
        #endif
    }
}
