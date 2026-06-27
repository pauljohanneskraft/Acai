import Foundation
import UMLCore

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
        case git(command: String, message: String)

        var errorDescription: String? {
            switch self {
            case .notAGitRepository(let path):
                "\(path) is not inside a git repository."
            case .git(let command, let message):
                "git \(command) failed: \(message)"
            }
        }
    }

    /// Analyzes the codebase's subtree at `reference` and returns the enriched artifact.
    func artifact(analyzer: CodebaseAnalyzer = .init()) throws -> CodeArtifact {
        let root = try runGit(["rev-parse", "--show-toplevel"], in: directory)
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
        _ = try runGit(archiveArgs, in: repoRoot)

        try runProcess(
            executable: "/usr/bin/tar", arguments: ["-x", "-f", tarURL.path, "-C", destination.path],
            commandLabel: "tar -x")
        try? FileManager.default.removeItem(at: tarURL)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        try runProcess(executable: "/usr/bin/git", arguments: arguments,
                       commandLabel: arguments.first ?? "git", workingDirectory: directory)
    }

    @discardableResult
    private func runProcess(
        executable: String, arguments: [String], commandLabel: String, workingDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.git(command: commandLabel, message: message ?? "exit \(process.terminationStatus)")
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
