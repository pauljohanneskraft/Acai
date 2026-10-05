import Foundation
import Testing
@testable import AcaiApp

/// Each message is compared against the resource it should have produced, built the same way — the
/// String Catalog is only compiled by Xcode, so asserting on resolved English would pass or fail
/// depending on which of the two test jobs ran it.
@Suite("Load failure messages")
struct LoadFailureTests {
    private struct Rejected: LocalizedError {
        var errorDescription: String? { "The server said no." }
    }

    private struct Bare: Error {}

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut])
    func aRequestThatNeverReachedAServerReadsAsOffline(_ code: URLError.Code) {
        let message = LoadFailure(error: URLError(code)).message

        #expect(String(localized: message) == String(localized: .app("Error.LoadFailure.Offline")))
    }

    @Test func aRejectedRequestKeepsItsOwnDescriptionAsTheDetail() {
        let message = LoadFailure(error: Rejected()).message

        #expect(String(localized: message)
            == String(localized: .app("Error.LoadFailure.Detail \("The server said no.")")))
        #expect(String(localized: message) != String(localized: .app("Error.LoadFailure.Offline")))
    }

    @Test func anErrorWithNoDescriptionOfItsOwnStillSaysSomething() {
        let error = Bare()

        #expect(String(localized: LoadFailure(error: error).message)
            == String(localized: .app("Error.LoadFailure.Detail \(error.localizedDescription)")))
    }

    @Test func aSpentRateLimitReachesTheDetailWithItsResetTime() throws {
        let failure = GitHubAPIClient.Failure.rateLimited(resetAt: Date(timeIntervalSinceNow: 600))
        let description = try #require(failure.errorDescription)

        #expect(String(localized: LoadFailure(error: failure).message)
            == String(localized: .app("Error.LoadFailure.Detail \(description)")))
    }
}
