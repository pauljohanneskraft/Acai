import Foundation
import Testing
@testable import AcaiApp

@Suite("ProjectStore GitHub-backed codebase count")
@MainActor
struct ProjectStoreGitHubCodebaseCountTests {
    private func makeStore() throws -> ProjectStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-github-count-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectStore(baseDir: url)
    }

    private func gitHubCodebase(_ name: String) -> Codebase {
        Codebase(
            name: name, directoryPath: "/tmp/\(name)",
            githubSource: GitHubSource(owner: "octocat", repo: name, ref: "main"))
    }

    @Test func countsOnlyGitHubBackedCodebasesAcrossProjects() throws {
        let store = try makeStore()
        store.projects = [
            Project(title: "A", subtitle: "", codebases: [
                gitHubCodebase("widgets"), Codebase(name: "local", directoryPath: "/tmp/local")
            ]),
            Project(title: "B", subtitle: "", codebases: [gitHubCodebase("gadgets")])
        ]

        #expect(store.gitHubBackedCodebaseCount == 2)
    }

    @Test func followsCodebasesAddedAndRemovedOnTheLiveStore() throws {
        let store = try makeStore()
        store.projects = [Project(title: "A", subtitle: "")]
        #expect(store.gitHubBackedCodebaseCount == 0)

        store.projects[0].codebases.append(gitHubCodebase("widgets"))
        #expect(store.gitHubBackedCodebaseCount == 1)

        store.projects[0].codebases.removeAll()
        #expect(store.gitHubBackedCodebaseCount == 0)
    }
}
