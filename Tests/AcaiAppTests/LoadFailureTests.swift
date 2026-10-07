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

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost
    ])
    func aRequestThatNeverLeftTheDeviceReadsAsOffline(_ code: URLError.Code) {
        #expect(message(for: URLError(code)) == String(localized: .app("Error.LoadFailure.Offline")))
        #expect(LoadFailure(error: URLError(code)).detail == nil)
    }

    @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost])
    func aServerThatDidNotAnswerIsNotCalledOffline(_ code: URLError.Code) {
        #expect(message(for: URLError(code)) == String(localized: .app("Error.LoadFailure.ServerUnresponsive")))
        #expect(message(for: URLError(code)) != String(localized: .app("Error.LoadFailure.Offline")))
        #expect(LoadFailure(error: URLError(code)).detail == nil)
    }

    @Test func anUnexpectedFailureKeepsItsOwnDescriptionForTheDisclosure() {
        let failure = LoadFailure(error: Rejected())

        #expect(String(localized: failure.message) == String(localized: .app("Error.LoadFailure.Unexpected")))
        #expect(failure.detail == "The server said no.")
    }

    @Test func anErrorWithNoDescriptionOfItsOwnStillHasADetail() {
        let error = Bare()

        #expect(LoadFailure(error: error).detail == error.localizedDescription)
    }

    @Test(arguments: [
        GitHubAPIClient.Failure.rateLimited(resetAt: Date(timeIntervalSinceNow: 600)),
        .rateLimited(resetAt: nil),
        .unauthorized
    ])
    func aSpentQuotaOrRejectedTokenIsShownAsItsOwnNextStep(_ failure: GitHubAPIClient.Failure) {
        #expect(message(for: failure) == String(localized: failure.message))
        #expect(LoadFailure(error: failure).detail == nil)
    }

    @Test func aRateLimitSaysWhenItResetsWithTheSystemRelativeFormat() {
        let resetAt = Date(timeIntervalSinceNow: 3 * 86_400 + 3_600)
        let when = resetAt.formatted(.relative(presentation: .named))

        #expect(String(localized: GitHubAPIClient.Failure.rateLimited(resetAt: resetAt).message)
            == String(localized: .app("Error.GitHubAPIClient.RateLimitedUntil \(when)")))
    }

    @Test func aPlainHTTPFailureIsUnexpectedWithTheResponseAsDetail() {
        let failure = GitHubAPIClient.Failure.http(403, "Resource not accessible")

        #expect(message(for: failure) == String(localized: .app("Error.LoadFailure.Unexpected")))
        #expect(LoadFailure(error: failure).detail == failure.errorDescription)
    }
}
