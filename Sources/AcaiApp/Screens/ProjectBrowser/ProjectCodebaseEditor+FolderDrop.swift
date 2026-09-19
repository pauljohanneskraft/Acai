import Foundation

/// A folder dropped onto a project, read while its drop grant was still live.
struct DroppedFolder: Sendable {
    let url: URL
    var securityScopedBookmark: SecurityScopedBookmark?
    var repository: CodebaseRepositoryReference?
}

struct FolderDropOutcome: Equatable {
    var added = 0
    var alreadyPresent = 0
}

extension ProjectCodebaseEditor {
    /// Adds each folder as a codebase named after it, skipping any the project already has.
    @discardableResult
    func addCodebases(from folders: [DroppedFolder], to projectID: UUID) -> FolderDropOutcome {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return FolderDropOutcome() }
        var knownPaths = Set(
            store.projects[index].codebases.map { URL(fileURLWithPath: $0.directoryPath).standardizedPath })
        var outcome = FolderDropOutcome()
        for folder in folders {
            guard knownPaths.insert(folder.url.standardizedPath).inserted else {
                outcome.alreadyPresent += 1
                continue
            }
            store.projects[index].codebases.append(Codebase(
                name: folder.url.lastPathComponent, directoryPath: folder.url.path,
                securityScopedBookmark: folder.securityScopedBookmark, repository: folder.repository))
            outcome.added += 1
        }
        if outcome.added > 0 { persist() }
        return outcome
    }
}

private extension URL {
    var standardizedPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }
}
