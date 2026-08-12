import Foundation
import Testing
@testable import AcaiApp

@Suite("RepositoryIndex (reverse index)")
struct RepositoryIndexTests {
    private func repositoryBackedCodebase(name: String, remoteURL: URL, ref: String = "main") -> Codebase {
        Codebase(
            name: name, directoryPath: "/tmp/\(name)",
            repository: CodebaseRepositoryReference(remoteURL: remoteURL, ref: ref))
    }

    @Test func codebasesWithNoRepositoryReferenceProduceNoEntries() {
        let project = Project(
            title: "P", subtitle: "",
            codebases: [Codebase(name: "plain", directoryPath: "/tmp/plain")])

        #expect(RepositoryIndex(projects: [project]).entries().isEmpty)
    }

    @Test func groupsCodebasesAcrossProjectsByRemoteURL() {
        let remoteA = URL(string: "https://github.com/acme/widgets.git")!
        let remoteB = URL(string: "https://github.com/acme/gadgets.git")!

        let projectOne = Project(
            title: "One", subtitle: "",
            codebases: [
                repositoryBackedCodebase(name: "widgets-main", remoteURL: remoteA, ref: "main"),
                repositoryBackedCodebase(name: "gadgets", remoteURL: remoteB)
            ])
        let projectTwo = Project(
            title: "Two", subtitle: "",
            codebases: [
                repositoryBackedCodebase(name: "widgets-feature", remoteURL: remoteA, ref: "feature")
            ])

        let entries = RepositoryIndex(projects: [projectOne, projectTwo]).entries()

        #expect(entries.count == 2)
        let widgetsEntry = entries.first { $0.remoteURL == remoteA }
        #expect(widgetsEntry?.codebases.count == 2)
        #expect(Set(widgetsEntry?.codebases.map(\.name) ?? []) == ["widgets-main", "widgets-feature"])

        let gadgetsEntry = entries.first { $0.remoteURL == remoteB }
        #expect(gadgetsEntry?.codebases.count == 1)
    }

    @Test func entriesAreSortedByRemoteURLForStableDisplayOrder() {
        let remoteZ = URL(string: "https://github.com/z/repo.git")!
        let remoteA = URL(string: "https://github.com/a/repo.git")!
        let project = Project(
            title: "P", subtitle: "",
            codebases: [
                repositoryBackedCodebase(name: "z", remoteURL: remoteZ),
                repositoryBackedCodebase(name: "a", remoteURL: remoteA)
            ])

        let entries = RepositoryIndex(projects: [project]).entries()

        #expect(entries.map(\.remoteURL) == [remoteA, remoteZ])
    }
}
