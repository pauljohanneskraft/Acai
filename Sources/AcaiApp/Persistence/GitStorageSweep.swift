import AcaiGit
import Foundation

/// Deletes shared clones and worktrees no codebase uses any more — what a deletion the app didn't
/// live to finish leaves behind. What counts as unused is decided against the codebases loaded at
/// launch, before the user can start adding one.
struct GitStorageSweep: Sendable {
    let orphanedWorktrees: [URL]
    let orphanedWorktreeNames: Set<String>
    let unreferencedClones: [URL]
    let locks: GitRepositoryLocks

    @MainActor
    init(store: ProjectStore) {
        let fileManager = FileManager.default
        let codebases = store.projects.flatMap(\.codebases)

        let codebaseIDs = Set(codebases.map(\.id.uuidString))
        let worktreeEntries = (try? fileManager.contentsOfDirectory(
            at: store.gitWorktreesDir, includingPropertiesForKeys: nil)) ?? []
        orphanedWorktrees = worktreeEntries.filter { !codebaseIDs.contains($0.lastPathComponent) }
        orphanedWorktreeNames = Set(orphanedWorktrees
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .map(store.gitWorktreeName(for:)))

        let referencedCloneNames = Set(codebases.compactMap(\.repository).map {
            GitRepository(remoteURL: $0.remoteURL, storeDirectory: store.gitRepositoriesDir).localPath.lastPathComponent
        })
        let cloneEntries = (try? fileManager.contentsOfDirectory(
            at: store.gitRepositoriesDir, includingPropertiesForKeys: nil)) ?? []
        unreferencedClones = cloneEntries
            .map(\.lastPathComponent)
            .filter { !referencedCloneNames.contains($0) }
            .map { store.gitRepositoriesDir.appendingPathComponent($0, isDirectory: true) }

        locks = store.gitRepositoryLocks
    }

    var isEmpty: Bool { orphanedWorktrees.isEmpty && unreferencedClones.isEmpty }

    func run() async {
        for worktree in orphanedWorktrees {
            try? FileManager.default.removeItem(at: worktree)
        }
        for clone in unreferencedClones {
            _ = try? await locks.run(forClonePath: clone) {
                guard !isInUse(clone) else { return }
                try FileManager.default.removeItem(at: clone)
            }
        }
    }

    /// Re-checked under the clone's lock: a worktree registered since launch belongs to a codebase
    /// being added for the same remote, which keeps the clone.
    private func isInUse(_ clone: URL) -> Bool {
        let names = (try? GitWorktree(repositoryDirectory: clone).list()) ?? []
        return names.contains { !orphanedWorktreeNames.contains($0) }
    }
}
