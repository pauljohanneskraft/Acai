import Foundation
import Testing
@testable import AcaiApp

/// Compares against the resource each case should produce, since only Xcode compiles the String Catalog.
@Suite("Load failure messages")
struct LoadFailureTests {
    private struct Rejected: LocalizedError {
        var errorDescription: String? { "The server said no." }
    }

    private struct Bare: Error {}

    private func message(for error: any Error) -> String {
        String(localized: LoadFailure(error: error).message)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut])
    func aRequestThatNeverReachedAServerReadsAsOffline(_ code: URLError.Code) {
        #expect(message(for: URLError(code)) == String(localized: .app("Error.LoadFailure.Offline")))
    }

    @Test func aRejectedRequestKeepsItsOwnDescriptionAsTheDetail() {
        #expect(message(for: Rejected())
            == String(localized: .app("Error.LoadFailure.Detail \("The server said no.")")))
    }

    @Test func anErrorWithNoDescriptionOfItsOwnStillSaysSomething() {
        let error = Bare()

        #expect(message(for: error)
            == String(localized: .app("Error.LoadFailure.Detail \(error.localizedDescription)")))
    }

    @Test(arguments: [
        GitHubAPIClient.Failure.rateLimited(resetAt: Date(timeIntervalSinceNow: 600)),
        .rateLimited(resetAt: nil),
        .unauthorized
    ])
    func aSpentQuotaOrRejectedTokenIsShownAsItsOwnNextStep(_ failure: GitHubAPIClient.Failure) {
        #expect(message(for: failure) == String(localized: failure.message))
        #expect(message(for: failure)
            != String(localized: .app("Error.LoadFailure.Detail \(failure.errorDescription ?? "")")))
    }

    @Test func aRateLimitSaysWhenItResetsWithTheSystemRelativeFormat() {
        let resetAt = Date(timeIntervalSinceNow: 3 * 86_400 + 3_600)
        let when = resetAt.formatted(.relative(presentation: .named))

        #expect(String(localized: GitHubAPIClient.Failure.rateLimited(resetAt: resetAt).message)
            == String(localized: .app("Error.GitHubAPIClient.RateLimitedUntil \(when)")))
    }

    @Test func aPlainHTTPFailureKeepsTheGenericFrame() {
        let failure = GitHubAPIClient.Failure.http(403, "Resource not accessible")

        #expect(message(for: failure)
            == String(localized: .app("Error.LoadFailure.Detail \(failure.errorDescription ?? "")")))
    }
}
