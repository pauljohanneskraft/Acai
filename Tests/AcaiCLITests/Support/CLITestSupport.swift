import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

/// Shared helpers for driving the CLI command tree in-process.
///
/// Commands are exercised through `AcaiCommand.parseAsRoot`, which runs ArgumentParser's parsing
/// *and* each command's `validate()`, so validation failures surface as thrown errors here exactly
/// as they would on the real command line. `run()` paths are reached by casting the parsed root to
/// the concrete subcommand. Filesystem fixtures live under a unique temp directory and are cleaned
/// up by the caller; tests never touch the user's `~/.config/acai`.
enum CLITestSupport {

    // MARK: - Parsing

    static func parseDiagram(_ arguments: [String]) throws -> AcaiCommand.Diagram {
        let root = try AcaiCommand.parseAsRoot(["diagram"] + arguments)
        return try #require(root as? AcaiCommand.Diagram)
    }

    static func parseAnalyze(_ arguments: [String]) throws -> AcaiCommand.Analyze {
        let root = try AcaiCommand.parseAsRoot(["analyze"] + arguments)
        return try #require(root as? AcaiCommand.Analyze)
    }

    static func parseMetrics(_ arguments: [String]) throws -> AcaiCommand.Metrics {
        let root = try AcaiCommand.parseAsRoot(["metrics"] + arguments)
        return try #require(root as? AcaiCommand.Metrics)
    }

    #if os(macOS)
    /// Parses `image`-subcommand `arguments` into the concrete `Image` command. macOS-only: the
    /// `image` subcommand needs SwiftUI's `ImageRenderer`, so it is not compiled on Linux.
    static func parseImage(_ arguments: [String]) throws -> AcaiCommand.Image {
        let root = try AcaiCommand.parseAsRoot(["image"] + arguments)
        return try #require(root as? AcaiCommand.Image)
    }
    #endif

    static func parseRulesInit(_ arguments: [String]) throws -> AcaiCommand.Rules.Init {
        let root = try AcaiCommand.parseAsRoot(["rules", "init"] + arguments)
        return try #require(root as? AcaiCommand.Rules.Init)
    }

    static func parseInspect(_ arguments: [String]) throws -> AcaiCommand.Inspect {
        let root = try AcaiCommand.parseAsRoot(["inspect"] + arguments)
        return try #require(root as? AcaiCommand.Inspect)
    }

    static func parseQuality(_ arguments: [String]) throws -> AcaiCommand.Quality {
        let root = try AcaiCommand.parseAsRoot(["quality"] + arguments)
        return try #require(root as? AcaiCommand.Quality)
    }

    static func parseCallGraph(_ arguments: [String]) throws -> AcaiCommand.CallGraph {
        let root = try AcaiCommand.parseAsRoot(["callgraph"] + arguments)
        return try #require(root as? AcaiCommand.CallGraph)
    }

    static func parseImpact(_ arguments: [String]) throws -> AcaiCommand.Impact {
        let root = try AcaiCommand.parseAsRoot(["impact"] + arguments)
        return try #require(root as? AcaiCommand.Impact)
    }

    static func message(for error: Error) -> String {
        AcaiCommand.message(for: error)
    }

    static func exitCode(for error: Error) -> ExitCode {
        AcaiCommand.exitCode(for: error)
    }

    // MARK: - Filesystem fixtures

    /// Creates a unique temporary directory and returns its URL. The caller is responsible for
    /// removing it (see `withTempDirectory`).
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs `body` with a fresh temp directory that is removed afterwards.
    static func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Writes a minimal two-type Swift source file (one type calls the other) into `directory`,
    /// producing a codebase that yields non-trivial class/sequence/call-graph diagrams.
    @discardableResult
    static func writeSampleSwiftSource(in directory: URL) throws -> URL {
        let source = """
        class Service {
            let repository: Repository = Repository()
            func run() {
                repository.save()
            }
        }

        class Repository {
            func save() {}
        }
        """
        let fileURL = directory.appendingPathComponent("Sample.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// A path under the temp directory that is guaranteed not to exist yet.
    static func nonexistentPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCLITests-missing-\(UUID().uuidString)")
            .path
    }
}
