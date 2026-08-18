import AcaiCore
import AcaiDiff

/// The file-level view of an `ArtifactDiff` — which source files a comparison's added/removed/
/// changed types live in — for `CompareGitPanel`'s changed-files list and the node filter tapping a
/// row drives.
struct CompareChangedFiles {
    let diff: ArtifactDiff
    let oldArtifact: CodeArtifact
    let newArtifact: CodeArtifact

    struct FileEntry: Identifiable, Hashable {
        var filePath: String
        var typeIDs: Set<String>
        var id: String { filePath }
    }

    var files: [FileEntry] {
        let newByID = Dictionary(
            newArtifact.flattened().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldByID = Dictionary(
            oldArtifact.flattened().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var typeIDsByFile: [String: Set<String>] = [:]
        for id in diff.addedTypes + diff.changedTypes.map(\.id) {
            guard let filePath = newByID[id]?.location?.filePath else { continue }
            typeIDsByFile[filePath, default: []].insert(id)
        }
        for id in diff.removedTypes {
            guard let filePath = oldByID[id]?.location?.filePath else { continue }
            typeIDsByFile[filePath, default: []].insert(id)
        }

        return typeIDsByFile
            .map { FileEntry(filePath: $0.key, typeIDs: $0.value) }
            .sorted { $0.filePath < $1.filePath }
    }
}
