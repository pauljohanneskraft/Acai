import SwiftUI

struct NewProjectSheet: View {
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subtitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Subtitle", text: $subtitle)
                }
            }
            #if os(macOS)
            .frame(maxWidth: 360)
            #endif
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(title, subtitle)
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
    }
}
