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

// `.serialized`: every test here (plus the clone tests in `GitHubRepositoryCloneTests.swift`,
// an extension of this same suite type) installs a handler on `MockURLProtocol`'s shared static
// state — Swift Testing parallelizes across suites/tests by default, which would let one test's
// handler leak into another's in-flight request. One serialized suite is the fix.
@Suite("GitHub networking (API client + repository clone)", .serialized)
struct GitHubNetworkingTests {

    private func makeClient(credential: GitHubCredential) -> GitHubAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubAPIClient(credential: credential, session: URLSession(configuration: configuration))
    }

    @Test func headCommitSHARequestsCorrectPathAndAuthHeader() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode(["sha": "abc123"]))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("secret-token"))
        let sha = try await client.headCommitSHA(owner: "acme", repo: "widgets", ref: "main")

        #expect(sha == "abc123")
        #expect(capturedRequest?.url?.path == "/repos/acme/widgets/commits/main")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test func branchesRequestsExpectedPathAndPageSize() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try JSONEncoder().encode([["name": "main"], ["name": "develop"]]))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        let refs = try await client.branches(owner: "acme", repo: "widgets")

        #expect(refs.map(\.name) == ["main", "develop"])
        #expect(capturedRequest?.url?.path == "/repos/acme/widgets/branches")
        #expect(capturedRequest?.url?.query?.contains("per_page=100") == true)
    }

    @Test func repositoriesRequestsRequestedPageAtSharedPageSize() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        _ = try await client.repositories(page: 2)

        #expect(capturedRequest?.url?.query?.contains("page=2") == true)
        #expect(
            capturedRequest?.url?.query?.contains("per_page=\(GitHubAPIClient.repositoriesPerPage)") == true
        )
    }

    @Test func zipballDataSendsBearerTokenAndReturnsBodyVerbatim() async throws {
        let payload = Data("not-really-a-zip".utf8)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("secret-token"))
        let data = try await client.zipballData(owner: "acme", repo: "widgets", ref: "main")

        #expect(data == payload)
    }

    @Test func httpErrorStatusSurfacesAsFailure() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data("not found".utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let client = makeClient(credential: .personalAccessToken("t"))
        await #expect(throws: (any Error).self) {
            _ = try await client.headCommitSHA(owner: "acme", repo: "widgets", ref: "missing")
        }
    }
}
