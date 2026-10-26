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

/// An insertion's result for a caller that has to select one of the new rows rather than only count
/// them — a sidebar selection needs the id, which `FolderDropOutcome` deliberately doesn't carry.
struct CodebaseInsertion: Equatable {
    var addedIDs: [UUID] = []
    var alreadyPresent = 0
}

extension ProjectCodebaseEditor {
    /// Adds each folder as a codebase named the way the sheet names it, skipping any the project already has.
    @discardableResult
    func addCodebases(from folders: [DroppedFolder], to projectID: UUID) -> FolderDropOutcome {
        let insertion = insertCodebases(from: folders, to: projectID)
        return FolderDropOutcome(added: insertion.addedIDs.count, alreadyPresent: insertion.alreadyPresent)
    }

    func insertCodebases(from folders: [DroppedFolder], to projectID: UUID) -> CodebaseInsertion {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return CodebaseInsertion() }
        var knownPaths = Set(
            store.projects[index].codebases.map { URL(fileURLWithPath: $0.directoryPath).standardizedPath })
        var insertion = CodebaseInsertion()
        for folder in folders {
            guard knownPaths.insert(folder.url.standardizedPath).inserted else {
                insertion.alreadyPresent += 1
                continue
            }
            let codebase = Codebase(
                name: uniqueCodebaseName(
                    LocalFolderCodebaseName(folderURL: folder.url, repository: folder.repository).value,
                    inProjectAt: index),
                directoryPath: folder.url.path,
                securityScopedBookmark: folder.securityScopedBookmark, repository: folder.repository)
            store.projects[index].codebases.append(codebase)
            insertion.addedIDs.append(codebase.id)
        }
        if !insertion.addedIDs.isEmpty { persist() }
        return insertion
    }
}

private extension URL {
    var standardizedPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }
}
