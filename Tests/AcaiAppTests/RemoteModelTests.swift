import Foundation
import Testing
@testable import AcaiApp

@Suite("Host-neutral remote model")
struct RemoteModelTests {
    private let gitHubURL = URL(string: "https://github.com/acme/widgets.git")!
    private let gitLabURL = URL(string: "https://gitlab.example.com/team/widgets.git")!

    @Test func gitHubIsRecognisedFromTheRemoteURLAndEverythingElseIsGeneric() {
        #expect(RemoteHost(remoteURL: gitHubURL) == .github(owner: "acme", repo: "widgets"))
        #expect(RemoteHost(remoteURL: URL(string: "https://GitHub.com/acme/widgets")!)
            == .github(owner: "acme", repo: "widgets"))
        #expect(RemoteHost(remoteURL: gitLabURL) == .generic)
        #expect(RemoteHost(remoteURL: URL(fileURLWithPath: "/tmp/repo")) == .generic)
        #expect(RemoteHost(remoteURL: URL(string: "https://github.com/acme")!) == .generic)
    }

    @Test func aGitHubTokenIsOnlyEverSentToGitHub() {
        let credential = GitHubCredential.personalAccessToken("secret")

        let gitHub = RemoteEndpoint(remoteURL: gitHubURL, gitHubCredential: credential)
        #expect(gitHub.transportURL.user == "x-access-token")
        #expect(gitHub.transportURL.password == "secret")
        #expect(gitHub.remoteURL == gitHubURL)

        let gitLab = RemoteEndpoint(remoteURL: gitLabURL, gitHubCredential: credential)
        #expect(gitLab.transportURL == gitLabURL)

        let signedOut = RemoteEndpoint(remoteURL: gitHubURL, gitHubCredential: nil)
        #expect(signedOut.transportURL == gitHubURL)
    }

    @Test func remoteDisplayNameIsHostAndPathWithoutTheGitSuffix() {
        #expect(CodebaseRepositoryReference(remoteURL: gitLabURL, ref: "main").remoteDisplayName
            == "gitlab.example.com/team/widgets")
        #expect(CodebaseRepositoryReference(remoteURL: URL(fileURLWithPath: "/srv/repo.git"), ref: "main")
            .remoteDisplayName == "/srv/repo")
    }

    @Test func typedAddressesAreValidatedBeforeAnythingIsFetched() {
        #expect(RemoteAddress(text: " https://gitlab.example.com/team/widgets.git ").result == .success(gitLabURL))
        #expect(RemoteAddress(text: "/srv/repo").result == .success(URL(fileURLWithPath: "/srv/repo")))
        #expect(RemoteAddress(text: "").result == .failure(.empty))
        #expect(RemoteAddress(text: "git@github.com:acme/widgets.git").result == .failure(.unsupportedScheme))
        #expect(RemoteAddress(text: "ssh://git@host/repo.git").result == .failure(.unsupportedScheme))
        #expect(RemoteAddress(text: "https://user:token@host/repo.git").result == .failure(.containsCredentials))
        #expect(RemoteAddress(text: "https://").result == .failure(.malformed))
    }

    @Test func onlyAReportedSizeOverTheThresholdWarrantsAWarning() {
        let policy = CloneSizePolicy(thresholdKilobytes: 100)
        #expect(policy.warrantsWarning(sizeKilobytes: 101))
        #expect(!policy.warrantsWarning(sizeKilobytes: 100))
        #expect(!policy.warrantsWarning(sizeKilobytes: nil))
    }

    @Test func aCodebasePersistedWithTheLegacyGitHubSourceMigratesToAManagedCheckout() throws {
        let json = Data("""
        {
            "id": "7E0A1D6C-2E8B-4F57-9C1E-1A2B3C4D5E6F",
            "name": "widgets",
            "directoryPath": "/tmp/worktree",
            "githubSource": {
                "owner": "acme", "repo": "widgets", "ref": "v1", "refKind": "tag",
                "lastSyncedCommitSHA": "abc123", "lastSyncedAt": 0
            }
        }
        """.utf8)

        let codebase = try JSONDecoder().decode(Codebase.self, from: json)

        #expect(codebase.managedCheckout?.refKind == .tag)
        #expect(codebase.managedCheckout?.lastSyncedCommitSHA == "abc123")
        // No `repository`: a per-codebase clone, which `ProjectStore` discards on load.
        #expect(codebase.repository == nil)
    }

    @Test func aLegacySourceWithoutRefKindMigratesAsABranchAndKeepsItsRepository() throws {
        let json = Data("""
        {
            "name": "widgets",
            "directoryPath": "/tmp/worktree",
            "githubSource": { "owner": "acme", "repo": "widgets", "ref": "main" },
            "repository": { "remoteURL": "https://github.com/acme/widgets", "ref": "main" }
        }
        """.utf8)

        let codebase = try JSONDecoder().decode(Codebase.self, from: json)

        #expect(codebase.managedCheckout?.refKind == .branch)
        #expect(codebase.repository?.remoteURL == URL(string: "https://github.com/acme/widgets"))
    }

    @Test func encodingNeverWritesTheLegacyKeyAndRoundTripsTheNewFields() throws {
        var codebase = Codebase(name: "widgets", directoryPath: "/tmp/worktree")
        codebase.managedCheckout = ManagedCheckout(refKind: .tag, lastSyncedCommitSHA: "abc")
        codebase.repository = CodebaseRepositoryReference(remoteURL: gitLabURL, ref: "v2")
        codebase.analysedRevision = "v1"

        let data = try JSONEncoder().encode(codebase)
        let decoded = try JSONDecoder().decode(Codebase.self, from: data)

        #expect(String(bytes: data, encoding: .utf8)?.contains("githubSource") == false)
        #expect(decoded == codebase)
    }

    @Test func aPlainLocalFolderDecodesWithNoManagedCheckoutOrPinnedRevision() throws {
        let json = Data(#"{ "name": "local", "directoryPath": "/tmp/local" }"#.utf8)

        let codebase = try JSONDecoder().decode(Codebase.self, from: json)

        #expect(codebase.managedCheckout == nil)
        #expect(codebase.analysedRevision == nil)
        #expect(codebase.pinnedRevision == nil)
    }

    @Test func aManagedCheckoutIsNeverPinnedToAnotherRevision() {
        var codebase = Codebase(name: "widgets", directoryPath: "/tmp/worktree", analysedRevision: "v1")
        #expect(codebase.pinnedRevision == "v1")
        codebase.managedCheckout = ManagedCheckout()
        #expect(codebase.pinnedRevision == nil)
    }

    @Test func twoSpellingsOfOneRemoteAreOneRepository() {
        let plain = Codebase(
            name: "a", directoryPath: "/a",
            repository: CodebaseRepositoryReference(
                remoteURL: URL(string: "https://github.com/acme/widgets")!, ref: "main"))
        let suffixed = Codebase(
            name: "b", directoryPath: "/b",
            repository: CodebaseRepositoryReference(remoteURL: gitHubURL, ref: "dev"))

        let entries = RepositoryIndex(projects: [Project(title: "P", subtitle: "", codebases: [plain, suffixed])])
            .entries()

        #expect(entries.count == 1)
        #expect(entries.first?.codebases.count == 2)
    }
}
