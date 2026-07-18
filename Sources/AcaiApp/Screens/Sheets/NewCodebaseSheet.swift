import SwiftUI
import UniformTypeIdentifiers

struct NewCodebaseSheet: View {
    let projectID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var directoryURL: URL?
    @State private var securityScopedBookmark: SecurityScopedBookmark?
    @State private var isChoosingDirectory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Codebase").font(.title2).bold()
            TextField("Name", text: $name)
            HStack {
                Text(directoryURL?.path ?? "No directory chosen").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { isChoosingDirectory = true }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    if let dir = directoryURL {
                        model.editing.addCodebase(
                            to: projectID, name: name, directoryURL: dir,
                            securityScopedBookmark: securityScopedBookmark)
                    }
                    dismiss()
                }.disabled(name.isEmpty || directoryURL == nil)
            }
        }
        .padding()
        .frame(maxWidth: 480)
        .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            directoryURL = url
            securityScopedBookmark = try? SecurityScopedBookmark(resolving: url)
        }
    }
}
