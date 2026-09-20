import Foundation
import Testing
@testable import AcaiGit

@Suite("GitRemoteListing")
struct GitRemoteListingTests {
    @Test("Lists a remote's branches, tags and default branch without cloning it")
    func listsRefsWithoutCloning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture(directory: root).make()

        let listing = try await GitRemoteListing(remoteURL: root).list()

        #expect(listing.refs == [
            GitCheckout.Ref(name: "feature", kind: .branch),
            GitCheckout.Ref(name: "main", kind: .branch),
            GitCheckout.Ref(name: "v1", kind: .tag)
        ])
        #expect(listing.defaultBranch == "main")
    }

    @Test("An unreachable remote fails with a readable message")
    func unreachableRemoteFails() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        await #expect(throws: (any Error).self) { try await GitRemoteListing(remoteURL: missing).list() }
    }
}
