#if os(macOS)
import Foundation

/// A throwaway repository built with the `git` CLI (fixture setup only; the code under test never
/// shells out). `main` has `README.md`; `feature` is one commit ahead and adds `Feature.swift`.
struct GitTestRepository {
    let directory: URL

    struct CommandFailed: Error, CustomStringConvertible {
        let arguments: [String]
        let output: String
        var description: String { "git \(arguments.joined(separator: " ")) failed: \(output)" }
    }

    static func make(in parent: URL, named name: String = "remote") throws -> GitTestRepository {
        let repository = GitTestRepository(directory: parent.appendingPathComponent(name, isDirectory: true))
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        try repository.git("init", "-q", "--initial-branch=main")
        try repository.commit("README.md", "hello", message: "initial")
        try repository.git("checkout", "-q", "-b", "feature")
        try repository.commit("Feature.swift", "struct Feature {}", message: "feature work")
        try repository.git("checkout", "-q", "main")
        return repository
    }

    func commit(_ path: String, _ content: String, message: String) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_OPTIONAL_LOCKS": "0"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandFailed(arguments: arguments, output: String(bytes: errorOutput, encoding: .utf8) ?? "")
        }
        return (String(bytes: output, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
