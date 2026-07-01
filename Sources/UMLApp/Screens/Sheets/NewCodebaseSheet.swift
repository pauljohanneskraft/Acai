import SwiftUI

struct NewCodebaseSheet: View {
    let projectID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var directoryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Codebase").font(.title2).bold()
            TextField("Name", text: $name)
            HStack {
                Text(directoryURL?.path ?? "No directory chosen").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { pickDirectory() }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    if let dir = directoryURL {
                        model.editing.addCodebase(to: projectID, name: name, directoryURL: dir)
                    }
                    dismiss()
                }.disabled(name.isEmpty || directoryURL == nil)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func pickDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            directoryURL = panel.url
        }
        #endif
    }
}
