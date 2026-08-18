import SwiftUI

struct NewProjectSheet: View {
    private enum Field { case title, subtitle }

    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subtitle = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // `TextField`'s first parameter renders as an extra label inside `LabeledContent`
                    // on macOS, so a longer title (vs. "Optional") would misalign the two rows' field
                    // boxes. Use `prompt:` instead — internal placeholder text, not a second label.
                    LabeledContent("Title") {
                        TextField("", text: $title, prompt: Text("e.g. My Project"))
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .title)
                            .accessibilityIdentifier("newProjectSheet.titleField")
                    }
                    LabeledContent("Subtitle") {
                        TextField("", text: $subtitle, prompt: Text("Optional"))
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .subtitle)
                            .accessibilityIdentifier("newProjectSheet.subtitleField")
                    }
                }
            }
            #if os(macOS)
            // macOS's Form leaves almost no gap before the toolbar buttons; add padding here on
            // the Form itself, not the Section (Section-level padding distributes per row and
            // throws off the Title field's vertical centering). iOS already has enough room.
            .padding(.bottom, 8)
            .frame(maxWidth: 360)
            #else
            .presentationDetents([.medium])
            #endif
            .onAppear { focusedField = .title }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("newProjectSheet.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(title, subtitle)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                    .accessibilityIdentifier("newProjectSheet.createButton")
                }
            }
        }
    }
}
