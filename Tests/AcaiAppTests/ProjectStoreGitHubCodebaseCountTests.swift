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

    private func reference(_ remote: String) -> CodebaseRepositoryReference {
        CodebaseRepositoryReference(remoteURL: URL(string: remote)!, ref: "main")
    }

    private func gitHubCodebase(_ name: String) -> Codebase {
        Codebase(
            name: name, directoryPath: "/tmp/\(name)", managedCheckout: ManagedCheckout(),
            repository: reference("https://github.com/octocat/\(name).git"))
    }

    /// A local folder tracking a GitHub origin and a clone from another host don't use the account.
    @Test func countsOnlyCodebasesClonedFromGitHubAcrossProjects() throws {
        let store = try makeStore()
        store.projects = [
            Project(title: "A", subtitle: "", codebases: [
                gitHubCodebase("widgets"),
                Codebase(name: "local", directoryPath: "/tmp/local"),
                Codebase(
                    name: "tracking", directoryPath: "/tmp/tracking",
                    repository: reference("https://github.com/octocat/tracking.git")),
                Codebase(
                    name: "gitlab", directoryPath: "/tmp/gitlab", managedCheckout: ManagedCheckout(),
                    repository: reference("https://gitlab.example.com/team/gitlab.git"))
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
