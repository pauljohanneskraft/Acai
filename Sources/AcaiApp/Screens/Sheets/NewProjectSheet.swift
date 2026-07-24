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
                    LabeledContent("Title") {
                        TextField("e.g. My Project", text: $title)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .title)
                            .accessibilityIdentifier("newProjectSheet.titleField")
                    }
                    LabeledContent("Subtitle") {
                        TextField("Optional", text: $subtitle)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .subtitle)
                            .accessibilityIdentifier("newProjectSheet.subtitleField")
                    }
                }
                // The Form's own bottom inset leaves almost no gap before the toolbar's Cancel/
                // Create buttons on macOS — add a little breathing room explicitly.
                .padding(.bottom, 8)
            }
            #if os(macOS)
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
