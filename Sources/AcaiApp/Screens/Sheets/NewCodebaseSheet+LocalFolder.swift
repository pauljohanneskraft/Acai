import SwiftUI

extension NewCodebaseSheetContent {
    func chooseDirectory() {
        let fixtures = UITestFixtureResolver()
        guard fixtures.resolveBaseDir() != nil, let staged = fixtures.resolveLocalFolderURL() else {
            isChoosingDirectory = true
            return
        }
        // A staged folder is read by plain path, with no picker grant to bookmark.
        sheet.securityScopedBookmark = nil
        adoptDirectory(staged)
    }

    func pickDirectory(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            model.store.report(.app("Error.ScopedResourceAccess.Denied \(url.path)"))
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        // A bookmark that silently failed to mint is what breaks access after relaunch, so report
        // it rather than storing `nil`.
        do {
            sheet.securityScopedBookmark = try SecurityScopedBookmark(resolving: url)
        } catch {
            sheet.securityScopedBookmark = nil
            model.store.report(
                .app("Error.ScopedResourceAccess.BookmarkFailed \(url.path) \(error.localizedDescription)"))
        }
        adoptDirectory(url)
    }

    /// Call inside the folder's access window; the root walk reopens its own scope.
    private func adoptDirectory(_ url: URL) {
        sheet.directoryURL = url
        sheet.repositoryReference = LocalGitRepositoryDetector(directory: url).detect()
        sheet.discoverRoots()
    }

    var localFolderSection: some View {
        Section {
            #if os(macOS)
            LabeledContent {
                HStack {
                    directoryPathText
                    Button(.app("View.NewCodebaseSheet.Choose")) { chooseDirectory() }
                        .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
                }
            } label: {
                Text(.app("View.NewCodebaseSheet.Directory"))
            }
            #else
            HStack {
                directoryPathText
                Spacer()
                Button(.app("View.NewCodebaseSheet.Choose")) { chooseDirectory() }
                    .accessibilityIdentifier("newCodebase.chooseDirectoryButton")
            }
            #endif
        }
    }

    private var directoryPathText: some View {
        (sheet.directoryURL.map { Text(verbatim: $0.path) }
            ?? Text(.app("View.NewCodebaseSheet.NoDirectoryChosen")))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(sheet.directoryURL == nil ? .secondary : .primary)
    }
}
