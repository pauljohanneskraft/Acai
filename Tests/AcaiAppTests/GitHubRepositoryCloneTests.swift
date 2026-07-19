import Foundation
import Testing
import ZipArchive
@testable import AcaiApp

// An extension of `GitHubNetworkingTests` (declared in `GitHubAPIClientTests.swift`), not a
// separate suite — see that file's `.serialized` comment for why these must share one suite.
extension GitHubNetworkingTests {

    /// Builds a fixture zip shaped like a real GitHub zipball: everything nested one level under
    /// `topLevelName` (mimicking `{owner}-{repo}-{sha}/`), optionally with one symlink entry.
    private func makeFixtureZip(
        topLevelName: String,
        files: [String: String],
        symlink: (name: String, target: String)? = nil
    ) throws -> Data {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let sourceDir = workDir.appendingPathComponent(topLevelName, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        for (relativePath, contents) in files {
            let fileURL = sourceDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let symlink {
            let linkURL = sourceDir.appendingPathComponent(symlink.name)
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: symlink.target)
        }

        let zipURL = workDir.appendingPathComponent("fixture.zip")
        let succeeded = SSZipArchive.createZipFile(
            atPath: zipURL.path,
            withContentsOfDirectory: sourceDir.path,
            keepParentDirectory: true,
            compressionLevel: -1,
            password: nil,
            aes: false,
            progressHandler: nil,
            keepSymlinks: true
        )
        #expect(succeeded)
        return try Data(contentsOf: zipURL)
    }

    /// Installs a `MockURLProtocol` handler serving `headSHA` for the commits endpoint and
    /// `zipData` for the zipball endpoint, and returns a client wired to it.
    private func makeClient(headSHA: String, zipData: Data) -> GitHubAPIClient {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.contains("/commits/") == true {
                return (response, try JSONEncoder().encode(["sha": headSHA]))
            }
            return (response, zipData)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubAPIClient(credential: .personalAccessToken("t"), session: URLSession(configuration: configuration))
    }

    private func makeDestination() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "acai-clone-dest-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func syncStripsTopLevelDirectoryAndReturnsHeadSHA() async throws {
        let zip = try makeFixtureZip(
            topLevelName: "acme-widgets-abc123",
            files: [
                "README.md": "hello",
                "Sources/Widget.swift": "class Widget {}"
            ]
        )
        let client = makeClient(headSHA: "abc123", zipData: zip)
        defer { MockURLProtocol.handler = nil }
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        let sha = try await GitHubRepositoryClone(client: client, owner: "acme", repo: "widgets", ref: "main")
            .sync(into: destination)

        #expect(sha == "abc123")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Sources/Widget.swift").path))
        // The wrapping `acme-widgets-abc123` directory itself must not survive into the destination.
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("acme-widgets-abc123").path))
    }

    @Test func syncRejectsSymlinkEscapingDestination() async throws {
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let secret = outsideDir.appendingPathComponent("secret.txt")
        try "top secret".write(to: secret, atomically: true, encoding: .utf8)

        let zip = try makeFixtureZip(
            topLevelName: "acme-widgets-abc123",
            files: ["README.md": "hello"],
            symlink: (name: "escape", target: secret.path)
        )
        let client = makeClient(headSHA: "abc123", zipData: zip)
        defer { MockURLProtocol.handler = nil }
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }

        await #expect(throws: (any Error).self) {
            _ = try await GitHubRepositoryClone(client: client, owner: "acme", repo: "widgets", ref: "main")
                .sync(into: destination)
        }
        // A rejected sync must never populate the destination — the folder that was there before
        // (nothing, here) stays as it was.
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
