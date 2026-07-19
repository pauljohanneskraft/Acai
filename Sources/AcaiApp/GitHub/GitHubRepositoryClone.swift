import Foundation
import ZipArchive

/// Clones (or re-syncs) a GitHub repository ref into an app-owned local folder by downloading the
/// zip GitHub builds server-side for that ref and extracting it — no `git` protocol, no bundled
/// executable. Once extracted, the folder is a plain directory indexed by the same
/// `CodebaseAnalyzer` path as any other codebase; GitHub is purely how the folder got there.
struct GitHubRepositoryClone {
    let client: GitHubAPIClient
    let owner: String
    let repo: String
    let ref: String

    enum Failure: LocalizedError {
        case unexpectedArchiveLayout
        case unsafeEntryPath(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedArchiveLayout:
                "GitHub's archive didn't have the expected single top-level folder."
            case .unsafeEntryPath(let path):
                "Refusing to extract \"\(path)\": its path escapes the destination folder."
            case .extractionFailed(let message):
                "Couldn't extract the downloaded archive: \(message)"
            }
        }
    }

    /// Downloads and extracts `ref` into `destination`, replacing its current contents (if any)
    /// only once extraction has fully succeeded and passed the path-safety check below — a failed
    /// sync leaves whatever was there before untouched. Returns the ref's head commit SHA.
    @discardableResult
    func sync(into destination: URL) async throws -> String {
        let headSHA = try await client.headCommitSHA(owner: owner, repo: repo, ref: ref)
        let zipData = try await client.zipballData(owner: owner, repo: repo, ref: ref)

        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let zipURL = workDir.appendingPathComponent("archive.zip")
        try zipData.write(to: zipURL)

        let extractedRoot = workDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

        var extractionError: NSError?
        let succeeded = SSZipArchive.unzipFile(
            atPath: zipURL.path,
            toDestination: extractedRoot.path,
            preserveAttributes: false,
            overwrite: true,
            symlinksValidWithin: extractedRoot.path,
            nestedZipLevel: 0,
            password: nil,
            error: &extractionError,
            delegate: nil,
            progressHandler: nil,
            completionHandler: nil
        )
        guard succeeded else {
            throw Failure.extractionFailed(extractionError?.localizedDescription ?? "unknown error")
        }

        let repoRoot = try soleTopLevelDirectory(in: extractedRoot)
        try validateNoPathEscapes(in: repoRoot)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: repoRoot, to: destination)

        return headSHA
    }

    /// GitHub zipballs wrap everything in one top-level `{owner}-{repo}-{sha}/` directory.
    private func soleTopLevelDirectory(in extractedRoot: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(
            at: extractedRoot, includingPropertiesForKeys: [.isDirectoryKey])
        guard entries.count == 1,
              (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            throw Failure.unexpectedArchiveLayout
        }
        return entries[0]
    }

    /// Defense in depth alongside `symlinksValidWithin:` above: walks every produced entry and
    /// confirms its resolved path — and, for symlinks, its resolved target — stays within `root`.
    /// Archive contents come from a third party (whatever repo the user points at), so this isn't
    /// something to rely on a single library layer for.
    private func validateNoPathEscapes(in root: URL) throws {
        let standardizedRoot = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ) else { return }
        for case let url as URL in enumerator {
            let standardizedPath = url.standardizedFileURL.path
            guard standardizedPath == standardizedRoot || standardizedPath.hasPrefix(standardizedRoot + "/") else {
                throw Failure.unsafeEntryPath(url.path)
            }
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            if isSymlink {
                let target = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard target == standardizedRoot || target.hasPrefix(standardizedRoot + "/") else {
                    throw Failure.unsafeEntryPath(url.path)
                }
            }
        }
    }
}
