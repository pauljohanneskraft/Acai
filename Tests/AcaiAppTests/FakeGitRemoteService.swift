import AcaiGit
import AcaiTestSupport
import Foundation
@testable import AcaiApp

/// Canned answers keyed by remote URL, plus a log of every call, so a model over `GitRemoteService`
/// is proven without git. `listingGate`, when set, holds every listing open until the test opens it.
final class FakeGitRemoteService: GitRemoteService, @unchecked Sendable {
    struct UnknownRemote: Error {}

    let listings = Locked<[URL: GitRemoteListing.Result]>([:])
    let failure = Locked<Error?>(nil)
    let listingGate = Locked<AsyncGate?>(nil)
    let inspections = Locked<[URL: CloneInspection]>([:])
    let sizes = Locked<[URL: Int64]>([:])
    let calls = Locked<[String]>([])

    func listRemote(_ endpoint: RemoteEndpoint) async throws -> GitRemoteListing.Result {
        record("listRemote", endpoint)
        if let gate = listingGate.value { await gate.wait() }
        if let error = failure.value { throw error }
        guard let listing = listings.value[endpoint.remoteURL] else { throw UnknownRemote() }
        return listing
    }

    @discardableResult
    func attachWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (headSHA: String, remoteURL: URL) {
        record("attachWorktree \(target.ref) \(target.depth)", target.endpoint)
        return ("sha-\(target.ref)", target.endpoint.remoteURL)
    }

    @discardableResult
    func resyncWorktree(
        _ target: RemoteCheckoutTarget, destination: GitWorktreeDestination,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> String {
        record("resyncWorktree \(target.ref)", target.endpoint)
        return "sha-\(target.ref)"
    }

    func refs(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async throws -> [GitCheckout.Ref] {
        record("refs", endpoint)
        return listings.value[endpoint.remoteURL]?.refs ?? []
    }

    func fetchFullHistory(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        record("fetchFullHistory", endpoint)
        inspections.withValue { $0[endpoint.remoteURL]?.isShallow = false }
    }

    func fetch(
        _ endpoint: RemoteEndpoint, hubStoreDirectory: URL, locks: GitRepositoryLocks,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        record("fetch", endpoint)
        if let error = failure.value { throw error }
        inspections.withValue { $0[endpoint.remoteURL]?.lastFetchedAt = Date() }
    }

    func inspectClone(_ endpoint: RemoteEndpoint, hubStoreDirectory: URL) async -> CloneInspection {
        record("inspectClone", endpoint)
        return inspections.value[endpoint.remoteURL] ?? .absent
    }

    func onDiskSize(of endpoint: RemoteEndpoint, hubStoreDirectory: URL) async -> Int64? {
        record("onDiskSize", endpoint)
        return sizes.value[endpoint.remoteURL]
    }

    func callCount(of name: String) -> Int {
        calls.value.filter { $0.hasPrefix(name) }.count
    }

    private func record(_ name: String, _ endpoint: RemoteEndpoint) {
        calls.withValue { $0.append("\(name) \(endpoint.remoteURL.absoluteString)") }
    }
}
