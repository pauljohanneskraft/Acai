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
                    // `TextField(_:text:)`'s first parameter isn't purely an internal placeholder
                    // on macOS inside a `LabeledContent` row — confirmed empirically it renders as a
                    // second, external label ahead of the field's own box, so "e.g. My Project"
                    // (longer than "Optional") pushed the Title field's box to a different leading
                    // position/width than Subtitle's. The `prompt:` parameter is unambiguously
                    // internal placeholder text, keeping both rows' label to just "Title"/
                    // "Subtitle" and both field boxes the same width.
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
            // The Form's own bottom inset leaves almost no gap before the toolbar's Cancel/Create
            // buttons on macOS — add a little breathing room explicitly. (Applied to the Form
            // itself, not the Section — a Section-level padding is distributed per row instead of
            // once at the bottom, which pushed the Title field's vertical centering off.) iOS's
            // `.presentationDetents([.medium])` sheet already has enough room below the form, so
            // this is scoped to macOS only.
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
