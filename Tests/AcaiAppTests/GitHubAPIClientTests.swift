import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

/// Serves canned responses for a `URLSession` without touching the network, keyed by whatever
/// `handler` a test installs. Tests run serially within this suite, so a single static handler is
/// enough; `nonisolated(unsafe)` reflects that it's deliberately unguarded test-only mutable state.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// `.serialized`: every test here (plus the remote-URL tests in `GitHubRemoteTests.swift`,
// an extension of this same suite type) installs a handler on `MockURLProtocol`'s shared static
// state — Swift Testing parallelizes across suites/tests by default, which would let one test's
// handler leak into another's in-flight request. One serialized suite is the fix.
@Suite("GitHub networking (API client + repository clone)", .serialized, .timeLimit(.minutes(1)))
struct GitHubNetworkingTests {

    private func makeClient(credential: GitHubCredential) -> GitHubAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubAPIClient(credential: credential, session: URLSession(configuration: configuration))
    }

    @Test func repositoriesDecodeSizeWhenPresentAndToleratesItsAbsence() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let owner: [String: Any] = ["login": "acme"]
            let body: [[String: Any]] = [
                ["id": 1, "name": "big", "full_name": "acme/big", "owner": owner, "default_branch": "main",
                 "private": false, "size": 812_000],
                ["id": 2, "name": "small", "full_name": "acme/small", "owner": owner, "default_branch": "main",
                 "private": true]
            ]
            return (response, try JSONSerialization.data(withJSONObject: body))
        }
        defer { MockURLProtocol.handler = nil }

        let repositories = try await makeClient(credential: .personalAccessToken("t")).repositories()

        #expect(repositories.map(\.sizeKilobytes) == [812_000, nil])
    }

    @Test func repositoriesRequestsRequestedPageAtSharedPageSize() async throws {
        let capturedRequest = Locked<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            capturedRequest.value = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        _ = try await client.repositories(page: 2)

        #expect(capturedRequest.value?.url?.query?.contains("page=2") == true)
        #expect(
            capturedRequest.value?.url?.query?.contains("per_page=\(GitHubAPIClient.repositoriesPerPage)") == true
        )
    }

    @Test func pullRequestsRequestsExpectedPathAndDecodesEachField() async throws {
        let capturedRequest = Locked<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            capturedRequest.value = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body: [[String: Any]] = [[
                "number": 42,
                "title": "Add widget support",
                "user": ["login": "octocat"],
                "base": ["ref": "main"],
                "head": ["ref": "feature/widget"],
                "state": "open"
            ]]
            return (response, try JSONSerialization.data(withJSONObject: body))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("secret-token"))
        let pullRequests = try await client.pullRequests(owner: "acme", repo: "widgets")

        #expect(pullRequests.count == 1)
        let pullRequest = try #require(pullRequests.first)
        #expect(pullRequest.number == 42)
        #expect(pullRequest.title == "Add widget support")
        #expect(pullRequest.authorLogin == "octocat")
        #expect(pullRequest.baseRef == "main")
        #expect(pullRequest.headRef == "feature/widget")
        #expect(pullRequest.state == "open")
        #expect(capturedRequest.value?.url?.path == "/repos/acme/widgets/pulls")
        #expect(capturedRequest.value?.url?.query?.contains("per_page=100") == true)
        #expect(capturedRequest.value?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    private func pullRequestsFailure(status: Int, headers: [String: String] = [:]) async -> (any Error)? {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (response, Data("refused".utf8))
        }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await makeClient(credential: .personalAccessToken("t")).pullRequests(owner: "acme", repo: "widgets")
            return nil
        } catch {
            return error
        }
    }

    private func rateLimitReset(status: Int, headers: [String: String]) async -> Date? {
        let failure = await pullRequestsFailure(status: status, headers: headers)
        guard case .rateLimited(let resetAt) = failure as? GitHubAPIClient.Failure else {
            Issue.record("expected a rate-limit failure, got \(String(describing: failure))")
            return nil
        }
        return resetAt
    }

    @Test(arguments: [403, 429])
    func aSpentQuotaCarriesItsResetTime(status: Int) async {
        let resetAt = await rateLimitReset(
            status: status, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000000"])

        #expect(resetAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test(arguments: [
        RateLimitedResponse(status: 403, headers: ["retry-after": "60"]),
        RateLimitedResponse(status: 429, headers: ["retry-after": "60"]),
        RateLimitedResponse(status: 429, headers: [
            "retry-after": "60", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000000"
        ])
    ])
    func aSecondaryLimitResetsAfterItsRetryAfter(_ response: RateLimitedResponse) async throws {
        let resetAt = await rateLimitReset(status: response.status, headers: response.headers)
        let seconds = try #require(resetAt).timeIntervalSinceNow

        #expect(seconds > 30 && seconds <= 60)
    }

    @Test func aRateLimitWithoutAResetHeaderInventsNoTime() async {
        #expect(await rateLimitReset(status: 429, headers: [:]) == nil)
    }

    @Test(arguments: [[:], ["x-ratelimit-remaining": "4999"]])
    func aForbiddenResponseWithQuotaLeftStaysAnOrdinaryFailure(_ headers: [String: String]) async {
        let failure = await pullRequestsFailure(status: 403, headers: headers)

        #expect(failure as? GitHubAPIClient.Failure == .http(403, "refused"))
    }

    @Test func aRejectedCredentialSurfacesAsUnauthorized() async {
        let failure = await pullRequestsFailure(status: 401)

        #expect(failure as? GitHubAPIClient.Failure == .unauthorized)
    }

    @Test func aRequestThatNeverReachesAServerReadsAsOffline() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        let thrown = await #expect(throws: URLError.self) {
            _ = try await client.pullRequests(owner: "acme", repo: "widgets")
        }

        #expect(String(localized: LoadFailure(error: try #require(thrown)).message)
            == String(localized: .app("Error.LoadFailure.Offline")))
    }

    @Test func httpErrorStatusSurfacesAsFailure() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data("not found".utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        await #expect(throws: (any Error).self) {
            _ = try await client.pullRequests(owner: "acme", repo: "widgets")
        }
    }
}

struct RateLimitedResponse: Sendable {
    var status: Int
    var headers: [String: String]
}
