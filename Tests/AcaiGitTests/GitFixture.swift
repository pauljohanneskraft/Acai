import Foundation

/// Shells out to `/usr/bin/git` (fixture setup only; the types under test never shell out).
/// `Process` is safe to use here because this target only ever builds on macOS.
///
/// `make()`/`makeWithRepeatedTouches()` build their fixture content once per process (`static let`
/// templates, computed via the real `git` command sequence below), then `directory` gets a plain
/// filesystem copy of that template — every call produced byte-identical content anyway (nothing
/// here varies per call site), so the ~13 real `git` subprocesses per call were pure waste across
/// the ~22 call sites in this test target.
struct GitFixture {
    let directory: URL

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // `GIT_CONFIG_*=/dev/null`: the runner carries a global git config (CI rewrites
        // `git@github.com:` to HTTPS), and a fixture repository must not inherit it.
        process.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandFailed(
                arguments: arguments, status: process.terminationStatus,
                output: String(data: errorData, encoding: .utf8) ?? ""
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    struct CommandFailed: Error, CustomStringConvertible {
        let arguments: [String]
        let status: Int32
        let output: String

        var description: String {
            "git \(arguments.joined(separator: " ")) exited \(status): \(output)"
        }
    }

    struct Commits {
        let initial: String
        let tagged: String
        let feature: String
    }

    private static func copyTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func makeTemplateDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiGitFixture-template-\(UUID().uuidString)", isDirectory: true)
    }

    // Built once per process, but the failure is carried rather than trapped: these are lazily
    // forced from whichever test touches them first, and a `try!` there would take down the entire
    // merged test process instead of failing the tests that actually need the fixture.
    private static let template: Result<(directory: URL, commits: Commits), Error> = Result {
        let directory = makeTemplateDirectory()
        return (directory, try GitFixture(directory: directory).buildTemplate())
    }

    private static let repeatedTouchesTemplate: Result<(directory: URL, headSHA: String), Error> = Result {
        let directory = makeTemplateDirectory()
        return (directory, try GitFixture(directory: directory).buildRepeatedTouchesTemplate())
    }

    @discardableResult
    func make() throws -> Commits {
        let template = try Self.template.get()
        try Self.copyTree(from: template.directory, to: directory)
        return template.commits
    }

    /// Independent of `make()`; gives `README.md` a churn count of 2 (the root commit contributes no
    /// touches — see `GitChurn`'s doc comment) and `Other.swift` a churn count of 1.
    @discardableResult
    func makeWithRepeatedTouches() throws -> String {
        let template = try Self.repeatedTouchesTemplate.get()
        try Self.copyTree(from: template.directory, to: directory)
        return template.headSHA
    }

    private func buildTemplate() throws -> Commits {
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

    private func buildRepeatedTouchesTemplate() throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run(["init", "--initial-branch=main"])

        try "v1".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try run(["add", "README.md"])
        try run(["commit", "-m", "add readme"])

        try "v2".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try run(["add", "README.md"])
        try run(["commit", "-m", "edit readme once"])

        try "other".write(to: directory.appendingPathComponent("Other.swift"), atomically: true, encoding: .utf8)
        try run(["add", "Other.swift"])
        try run(["commit", "-m", "add other file"])

        try "v3".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try run(["add", "README.md"])
        try run(["commit", "-m", "edit readme twice"])

        return try run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
