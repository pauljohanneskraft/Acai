import Foundation

/// Builds a small local git repository with real commit history, for `AcaiGit`'s tests to clone
/// from / open — via `/usr/bin/git` (fixture setup only; the types under test never shell out).
/// `swift test` only ever runs this target on a macOS host (this target is only built inside
/// `Package.swift`'s `#if canImport(SwiftUI)` block), so `Process` is always available here.
struct GitFixture {
    let directory: URL

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Creates the repository with two commits on `main` (the second tagged `v1`) and a `feature`
    /// branch one commit ahead. Returns the SHA of each commit of interest.
    struct Commits {
        let initial: String
        let tagged: String
        let feature: String
    }

    @discardableResult
    func make() throws -> Commits {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run(["init", "--initial-branch=main"])

        try "hello".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try run(["add", "README.md"])
        try run(["commit", "-m", "initial"])
        let initial = try run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try "world".write(
            to: directory.appendingPathComponent("Sub/Nested.swift"), atomically: true, encoding: .utf8)
        try run(["add", "Sub/Nested.swift"])
        try run(["commit", "-m", "add nested file"])
        let tagged = try run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try run(["tag", "v1"])

        try run(["checkout", "-b", "feature"])
        try "feature".write(
            to: directory.appendingPathComponent("Feature.swift"), atomically: true, encoding: .utf8)
        try run(["add", "Feature.swift"])
        try run(["commit", "-m", "feature work"])
        let feature = try run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

        try run(["checkout", "main"])

        return Commits(initial: initial, tagged: tagged, feature: feature)
    }
}
