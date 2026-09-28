import Foundation

/// What closing the source viewer is allowed to delete. A file shown at a pinned revision was
/// extracted from history into a temporary directory that nothing else owns, so it goes; a file read
/// from the working tree is the user's own and must be left exactly where it is.
struct SourceViewerSession: Equatable {
    var isPinnedRevision: Bool
    var shownURL: URL?

    var temporaryDirectoryToRemove: URL? {
        guard isPinnedRevision, let shownURL else { return nil }
        return shownURL.deletingLastPathComponent()
    }
}
