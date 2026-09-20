import SwiftUI

extension NewCodebaseSheet {
    func pickDirectory(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            model.store.report(.app("Error.ScopedResourceAccess.Denied \(url.path)"))
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        directoryURL = url
        // A bookmark that silently failed to mint is what breaks access after relaunch, so report
        // it rather than storing `nil`.
        do {
            securityScopedBookmark = try SecurityScopedBookmark(resolving: url)
        } catch {
            securityScopedBookmark = nil
            model.store.report(
                .app("Error.ScopedResourceAccess.BookmarkFailed \(url.path) \(error.localizedDescription)"))
        }
        // Reading the repository's config/HEAD must happen inside this same access window.
        repositoryReference = LocalGitRepositoryDetector(directory: url).detect()
    }

    var localFolderSection: some View {
        Section {
            nameField(isOptional: false, identifier: "newCodebase.localNameField")
            #if os(macOS)
            LabeledContent {
                HStack {
                    directoryPathText
                    Button(.app("View.NewCodebaseSheet.Choose")) { isChoosingDirectory = true }
                        .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
                }
            } label: {
                Text(.app("View.NewCodebaseSheet.Directory"))
            }
            #else
            HStack {
                directoryPathText
                Spacer()
                Button(.app("View.NewCodebaseSheet.Choose")) { isChoosingDirectory = true }
                    .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
            }
            #endif
        }
    }

    private var directoryPathText: some View {
        (directoryURL.map { Text(verbatim: $0.path) }
            ?? Text(.app("View.NewCodebaseSheet.NoDirectoryChosen")))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(directoryURL == nil ? .secondary : .primary)
    }
}
