import AcaiGit
import Foundation
import Testing
@testable import AcaiApp

@Suite("ProjectCodebaseEditor GitHub sync")
@MainActor
struct ProjectCodebaseEditorGitHubSyncTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-github-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFixtureService(refs: [String: [String: String]]) throws -> FastFixtureGitHubRepositoryService {
        let root = try makeTempDirectory()
        var sourceDirectoriesByRef: [String: URL] = [:]
        for (ref, files) in refs {
            let refDirectory = root.appendingPathComponent(ref, isDirectory: true)
            try FileManager.default.createDirectory(at: refDirectory, withIntermediateDirectories: true)
            for (relativePath, content) in files {
                try content.write(
                    to: refDirectory.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
            }
            sourceDirectoriesByRef[ref] = refDirectory
        }
        return FastFixtureGitHubRepositoryService(sourceDirectoriesByRef: sourceDirectoriesByRef)
    }

    private func makeEditor(store: ProjectStore, repositoryService: GitHubRepositoryService) -> ProjectCodebaseEditor {
        ProjectCodebaseEditor(
            store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in },
            repositoryService: repositoryService)
    }

    private let credential = GitHubCredential.personalAccessToken("fixture-token")

    @Test func addingACodebaseSetsGithubSourceAndRepositoryFields() async throws {
        let storeDir = try makeTempDirectory()
        let store = ProjectStore(baseDir: storeDir)
        let service = try makeFixtureService(refs: ["main": ["Widget.swift": "class Widget {}"]])
        let editor = makeEditor(store: store, repositoryService: service)
        let projectID = editor.addProject(title: "Demo", subtitle: "")

        await editor.addGitHubCodebase(
            to: projectID, name: "widgets", credential: credential,
            target: GitHubRepositoryRef(owner: "octocat", repo: "widgets", ref: "main", kind: .branch))

        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.githubSource?.owner == "octocat")
        #expect(codebase.githubSource?.repo == "widgets")
        #expect(codebase.githubSource?.ref == "main")
        #expect(codebase.repository != nil)
    }

    // `switchGitHubRef`/`pull` both read a signed-in account via a directly-instantiated, non-
    // injectable `GitHubTokenStore()` (real Keychain, unlike `addGitHubCodebase` above, which takes
    // its credential as a parameter) — with no account signed in, both must leave the codebase
    // untouched rather than attempt a sync, which is exactly the "no update on failure" half of
    // each method's own stated invariant, and the only half testable without writing to the real
    // system Keychain from a unit test.

    @Test func switchingRefWithNoSignedInAccountLeavesTheCodebaseUnchanged() async throws {
        let storeDir = try makeTempDirectory()
        let store = ProjectStore(baseDir: storeDir)
        let service = try makeFixtureService(refs: [
            "main": ["Widget.swift": "class Widget {}"],
            "feature": ["Widget.swift": "class Widget {}", "Extra.swift": "class Extra {}"]
        ])
        let editor = makeEditor(store: store, repositoryService: service)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        await editor.addGitHubCodebase(
            to: projectID, name: "widgets", credential: credential,
            target: GitHubRepositoryRef(owner: "octocat", repo: "widgets", ref: "main", kind: .branch))
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let shaAfterAdd = try #require(store.projects.first?.codebases.first?.githubSource?.lastSyncedCommitSHA)

        await editor.switchGitHubRef(codebaseID: codebaseID, ref: "feature", kind: .branch)

        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.githubSource?.ref == "main")
        #expect(codebase.repository?.ref == "main")
        #expect(codebase.githubSource?.lastSyncedCommitSHA == shaAfterAdd)
        #expect(!FileManager.default.fileExists(atPath: codebase.directoryPath + "/Extra.swift"))
    }

    @Test func pullWithNoSignedInAccountLeavesTheCodebaseUnchanged() async throws {
        let storeDir = try makeTempDirectory()
        let store = ProjectStore(baseDir: storeDir)
        let service = try makeFixtureService(refs: ["main": ["Widget.swift": "class Widget {}"]])
        let editor = makeEditor(store: store, repositoryService: service)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        await editor.addGitHubCodebase(
            to: projectID, name: "widgets", credential: credential,
            target: GitHubRepositoryRef(owner: "octocat", repo: "widgets", ref: "main", kind: .branch))
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)

        await editor.pull(codebaseID: codebaseID)
        let codebase = try #require(store.projects.first?.codebases.first)
        #expect(codebase.githubSource?.ref == "main")
    }
}
