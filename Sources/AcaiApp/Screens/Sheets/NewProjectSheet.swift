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
                    LabeledContent {
                        TextField("", text: $title, prompt: Text(.app("View.NewProjectSheet.EGMyProject")))
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .title)
                            .accessibilityIdentifier("newProjectSheet.titleField")
                    } label: {
                        Text(.app("View.NewProjectSheet.Title"))
                    }
                    LabeledContent {
                        TextField("", text: $subtitle, prompt: Text(.app("View.NewProjectSheet.Optional")))
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .subtitle)
                            .accessibilityIdentifier("newProjectSheet.subtitleField")
                    } label: {
                        Text(.app("View.NewProjectSheet.Subtitle"))
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
            .navigationTitle(.app("View.NewProjectSheet.NewProject"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.NewProjectSheet.Cancel")) { dismiss() }
                        .accessibilityIdentifier("newProjectSheet.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.NewProjectSheet.Create")) {
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
