// `Process` doesn't exist in the iOS SDK — macOS-only, see `GitCommand.swift`.
#if os(macOS)
import Foundation
import AcaiCore

/// Produces a codebase's `CodeArtifact` as it was at a git revision, for the diagram delta ("old"
/// side). It runs `git archive <ref>` to extract that revision's subtree into a temp directory and
/// analyzes it — **read-only**: the working tree, index and HEAD are never touched. The temp
/// directory is removed afterwards.
struct GitRevisionSnapshot {
    /// The codebase directory (may be the repo root or any subdirectory of it).
    let directory: URL
    /// A git revision: `HEAD`, a branch/tag name, a SHA, `HEAD~3`, …
    let reference: String

    enum Failure: LocalizedError {
        case notAGitRepository(String)
        case tarExtractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAGitRepository(let path):
                "\(path) is not inside a git repository."
            case .tarExtractionFailed(let message):
                "tar -x failed: \(message)"
            }
        }
    }

    /// Analyzes the codebase's subtree at `reference` and returns the enriched artifact.
    func artifact(analyzer: CodebaseAnalyzer = .init()) throws -> CodeArtifact {
        let root = try GitCommand(directory: directory, arguments: ["rev-parse", "--show-toplevel"]).run()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { throw Failure.notAGitRepository(directory.path) }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL

        let subpath = directory.standardizedFileURL.path.hasPrefix(rootURL.path + "/")
            ? String(directory.standardizedFileURL.path.dropFirst(rootURL.path.count + 1))
            : ""

        let temp = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: rootURL, create: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try extractArchive(reference: reference, subpath: subpath, repoRoot: rootURL, into: temp)
        let analyzeDir = subpath.isEmpty ? temp : temp.appendingPathComponent(subpath)
        return try analyzer.enrichedArtifact(at: analyzeDir)
    }

    /// `git archive <ref> [<subpath>]` → a tar, extracted into `destination`.
    private func extractArchive(reference: String, subpath: String, repoRoot: URL, into destination: URL) throws {
        let tarURL = destination.appendingPathComponent("snapshot.tar")
        var archiveArgs = ["-C", repoRoot.path, "archive", "--format=tar", "--output", tarURL.path, reference]
        if !subpath.isEmpty { archiveArgs.append(subpath) }
        try GitCommand(directory: repoRoot, arguments: archiveArgs).run()

        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["-x", "-f", tarURL.path, "-C", destination.path]
        let tarError = Pipe()
        tarProcess.standardError = tarError
        try tarProcess.run()
        let tarErrData = tarError.fileHandleForReading.readDataToEndOfFile()
        tarProcess.waitUntilExit()
        guard tarProcess.terminationStatus == 0 else {
            let message = String(data: tarErrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.tarExtractionFailed(message ?? "exit \(tarProcess.terminationStatus)")
        }
        try? FileManager.default.removeItem(at: tarURL)
    }
}
#endif
