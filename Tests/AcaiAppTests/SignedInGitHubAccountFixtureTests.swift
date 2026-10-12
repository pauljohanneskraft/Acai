import Foundation
import Testing
@testable import AcaiApp

/// `SeededFixture.stageSignedInGitHubAccount(in:)` copies `signed-in-github-token.json` over the
/// file a fixture launch redirects `GitHubTokenStore` to, so a journey that only needs an account
/// starts with one instead of driving the Settings sign-in form. That file is hand-written JSON on
/// the other side of the SwiftPM / Xcode-project boundary, where nothing type-checks it: this pins
/// it both to the shape `StoredAccount` reads and to what the form itself would have stored.
@Suite("Signed-in GitHub account fixture", .timeLimit(.minutes(1)))
@MainActor
struct SignedInGitHubAccountFixtureTests {
    private var stagedTokenFile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AcaiUITests/Fixtures/seeded/signed-in-github-token.json")
    }

    @Test func itCarriesTheTokenAndIdentityTheSignInFormWouldHaveProduced() throws {
        let staged = try #require(
            GitHubTokenStore(fileURL: stagedTokenFile).load(), "the staged GitHub account no longer decodes")

        #expect(staged.credential == .personalAccessToken("fixture-token"))
        #expect(staged.login == FixtureGitHubAccountService.login)
    }

    @Test func itHoldsExactlyWhatSigningInThroughTheFormStores() async throws {
        let staged = try #require(
            GitHubTokenStore(fileURL: stagedTokenFile).load(), "the staged GitHub account no longer decodes")

        let tokenFile = try makeTokenFile()
        defer { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
        let store = GitHubAccountStore(
            service: FixtureGitHubAccountService(), tokenStore: GitHubTokenStore(fileURL: tokenFile))
        try await store.signIn(with: staged.credential)

        #expect(store.account == staged)
    }

    private func makeTokenFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-signed-in-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("github-token.json")
    }
}
