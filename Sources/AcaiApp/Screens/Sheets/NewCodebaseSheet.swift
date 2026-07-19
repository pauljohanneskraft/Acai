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
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Directory") {
                        Text(directoryURL?.path ?? "No directory chosen")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(directoryURL == nil ? .secondary : .primary)
                    }
                    Button("Choose…") { isChoosingDirectory = true }
                }
            }
            #if os(macOS)
            .frame(maxWidth: 480)
            #endif
            .navigationTitle("Add Codebase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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
            .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
                guard let url = try? result.get() else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                directoryURL = url
                securityScopedBookmark = try? SecurityScopedBookmark(resolving: url)
            }
        }
    }
}
