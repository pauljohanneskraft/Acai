import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("Project Store git storage")
@MainActor
struct ProjectStoreGitStorageTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-git-storage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func gitHubSource() -> GitHubSource {
        GitHubSource(
            owner: "octocat", repo: "widgets", ref: "main", refKind: .branch,
            lastSyncedCommitSHA: nil, lastSyncedAt: nil)
    }

    private let remoteURL = URL(string: "https://github.com/octocat/widgets.git")!

    @Test func loadingDiscardsACodebaseWithItsOwnCloneAndKeepsTheOthers() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var perCodebaseClone = Codebase(name: "old", directoryPath: dir.appendingPathComponent("github-clones/x").path)
        perCodebaseClone.githubSource = gitHubSource()
        var sharedClone = Codebase(name: "new", directoryPath: dir.appendingPathComponent("git-worktrees/y").path)
        sharedClone.githubSource = gitHubSource()
        sharedClone.repository = CodebaseRepositoryReference(remoteURL: remoteURL, ref: "main")
        let local = Codebase(name: "local", directoryPath: "/tmp/local")

        let diagram = GeneratedDiagram(
            name: "Classes", content: .init(type: .classDiagram), codebaseID: perCodebaseClone.id)
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [perCodebaseClone, sharedClone, local]
        project.generatedDiagramIDs = [diagram.id]

        let store = ProjectStore(baseDir: dir)
        store.projects.append(project)
        store.saveProject(project)
        store.saveGeneratedDiagram(diagram)

        let reloaded = ProjectStore(baseDir: dir)

        #expect(reloaded.projects.first?.codebases.map(\.name) == ["new", "local"])
        #expect(reloaded.projects.first?.generatedDiagramIDs.isEmpty == true)
        #expect(reloaded.generatedDiagrams[diagram.id] == nil)
        #expect(ProjectStore(baseDir: dir).projects.first?.codebases.map(\.name) == ["new", "local"])
    }

    @Test func launchingDeletesThePerCodebaseCloneDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clones = dir.appendingPathComponent("github-clones", isDirectory: true)
        try FileManager.default.createDirectory(
            at: clones.appendingPathComponent(UUID().uuidString), withIntermediateDirectories: true)

        _ = ProjectStore(baseDir: dir)

        #expect(!FileManager.default.fileExists(atPath: clones.path))
    }

    @Test func sweepDeletesOnlyUnreferencedClonesAndWorktrees() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)

        var codebase = Codebase(name: "widgets", directoryPath: "")
        codebase.githubSource = gitHubSource()
        codebase.repository = CodebaseRepositoryReference(remoteURL: remoteURL, ref: "main")
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]

        let fileManager = FileManager.default
        let referencedClone = GitRepository(remoteURL: remoteURL, storeDirectory: store.gitRepositoriesDir).localPath
        let unreferencedClone = store.gitRepositoriesDir.appendingPathComponent("unreferenced", isDirectory: true)
        let liveWorktree = store.gitWorktreeURL(for: codebase.id)
        let orphanedWorktree = store.gitWorktreeURL(for: UUID())
        for directory in [referencedClone, unreferencedClone, liveWorktree, orphanedWorktree] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        await GitStorageSweep(store: store).run()

        #expect(fileManager.fileExists(atPath: referencedClone.path))
        #expect(fileManager.fileExists(atPath: liveWorktree.path))
        #expect(!fileManager.fileExists(atPath: unreferencedClone.path))
        #expect(!fileManager.fileExists(atPath: orphanedWorktree.path))
    }

    @Test func sweepIsEmptyWhenEverythingIsReferenced() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)

        #expect(GitStorageSweep(store: store).isEmpty)
    }
}
