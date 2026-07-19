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

    /// A zip built with the real `zip` CLI (not `SSZipArchive`'s own directory-zipping API, which
    /// can't produce this shape at all — the filesystem would resolve the `..` before zipping)
    /// containing two entries, `../../../outside.txt` and `README.md`, with no wrapping top-level
    /// directory at all. This is the most realistic hand-crafted "raw traversal entry" a malicious
    /// zipball could contain, straight from `unzip -l`:
    /// ```
    ///        11  ../../../outside.txt
    ///         6  README.md
    /// ```
    private func rawTraversalEntryZip() -> Data {
        Data(
            base64Encoded: """
            UEsDBAoAAAAAALu181wRA8JzCwAAAAsAAAAUAAAALi4vLi4vLi4vb3V0c2lkZS50eHR0b3Agc2Vj\
            cmV0ClBLAwQKAAAAAAC7tfNcIDA6NgYAAAAGAAAACQAAAFJFQURNRS5tZGhlbGxvClBLAQIeAwoA\
            AAAAALu181wRA8JzCwAAAAsAAAAUAAAAAAAAAAEAAACkgQAAAAAuLi8uLi8uLi9vdXRzaWRlLnR4\
            dFBLAQIeAwoAAAAAALu181wgMDo2BgAAAAYAAAAJAAAAAAAAAAEAAACkgT0AAABSRUFETUUubWRQ\
            SwUGAAAAAAIAAgB5AAAAagAAAAAA
            """
        )!
    }

    @Test func syncRejectsRawTraversalEntryWithNoWrappingDirectory() async throws {
        let client = makeClient(headSHA: "abc123", zipData: rawTraversalEntryZip())
        defer { MockURLProtocol.handler = nil }
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let outsideMarker = destination.deletingLastPathComponent()
            .appendingPathComponent("outside.txt")
        try? FileManager.default.removeItem(at: outsideMarker)

        // Two entries with no shared wrapping directory don't match a real GitHub zipball's shape
        // (always exactly one top-level directory), so `soleTopLevelDirectory` rejects this archive
        // before extraction contents are ever trusted — regardless of whether minizip-ng itself
        // sanitized the `../` segments in the traversal entry.
        await #expect(throws: (any Error).self) {
            _ = try await GitHubRepositoryClone(client: client, owner: "acme", repo: "widgets", ref: "main")
                .sync(into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        // And even if it hadn't been rejected on shape alone, the traversal entry must never have
        // escaped anywhere near the destination's parent directory.
        #expect(!FileManager.default.fileExists(atPath: outsideMarker.path))
    }

    /// A zip (again built with the real `zip` CLI) shaped like a real GitHub zipball — a single
    /// top-level `wrapper/` directory, which passes `soleTopLevelDirectory`'s shape check — but
    /// containing a second entry `wrapper/../../escape-marker.txt` whose raw `..` segments cancel
    /// out `wrapper` and one more level, i.e. a traversal *nested inside* the sole wrapper
    /// directory rather than a sibling of it. This is the shape `syncRejectsRawTraversalEntryWithNoWrappingDirectory`
    /// above does NOT cover (that fixture's two top-level entries get rejected on shape alone,
    /// before the traversal ever matters) — this one isolates whether extraction sanitization
    /// alone would let a traversal through a real zipball's shape escape undetected.
    private func nestedTraversalEntryZip() -> Data {
        Data(
            base64Encoded: """
            UEsDBAoAAAAAAM4J9FwgMDo2BgAAAAYAAAARAAAAd3JhcHBlci9SRUFETUUubWRoZWxsbwpQSwME\
            CgAAAAAAzgn0XBEDwnMLAAAACwAAAB8AAAB3cmFwcGVyLy4uLy4uL2VzY2FwZS1tYXJrZXIudHh0\
            dG9wIHNlY3JldApQSwECHgMKAAAAAADOCfRcIDA6NgYAAAAGAAAAEQAAAAAAAAABAAAApIEAAAAA\
            d3JhcHBlci9SRUFETUUubWRQSwECHgMKAAAAAADOCfRcEQPCcwsAAAALAAAAHwAAAAAAAAABAAAA\
            pIE1AAAAd3JhcHBlci8uLi8uLi9lc2NhcGUtbWFya2VyLnR4dFBLBQYAAAAAAgACAIwAAAB9AAAA\
            AAA=
            """
        )!
    }

    @Test func syncRejectsNestedTraversalEntryInsideSoleWrapperDirectory() async throws {
        let client = makeClient(headSHA: "abc123", zipData: nestedTraversalEntryZip())
        defer { MockURLProtocol.handler = nil }
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(at: destination) }
        let outsideMarker = destination.deletingLastPathComponent()
            .appendingPathComponent("escape-marker.txt")
        try? FileManager.default.removeItem(at: outsideMarker)

        // minizip-ng clamps the `..` segments to stay within the extraction root, which turns the
        // traversal entry into a sibling of `wrapper/` rather than letting it write outside the
        // extraction root entirely — so `soleTopLevelDirectory`'s single-entry check rejects the
        // resulting two-entry layout, same as the sibling-entries fixture above, but for a
        // genuinely different reason (extraction-time clamping, not the fixture's own shape).
        await #expect(throws: (any Error).self) {
            _ = try await GitHubRepositoryClone(client: client, owner: "acme", repo: "widgets", ref: "main")
                .sync(into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: outsideMarker.path))
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
