import SwiftUI

struct NewProjectSheet: View {
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subtitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Project").font(.title2).bold()
            TextField("Title", text: $title)
            TextField("Subtitle", text: $subtitle)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(title, subtitle)
                    dismiss()
                }.disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(maxWidth: 360)
    }
}
