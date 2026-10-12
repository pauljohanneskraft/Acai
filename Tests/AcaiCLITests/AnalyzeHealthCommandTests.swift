import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Analyze Health Command")
struct AnalyzeHealthCommandTests {

    @Test func cleanSourceScoresPerfect() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("health.json")
            var cmd = try CLITestSupport.parseAnalyze(
                ["--source", dir.path, "--language", "swift", "--health", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"score\" : 1"))
            #expect(contents.contains("\"diagnosticCount\" : 0"))
            #expect(contents.contains("\"typeCount\""))
        }
    }

    /// The scope the parse ran over is in the JSON under a name a caller can rely on, with the
    /// directories each root contributed.
    @Test func jsonCarriesTheDiscoveredRoots() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("health.json")
            var cmd = try CLITestSupport.parseAnalyze(
                ["--source", dir.path, "--language", "swift", "--health", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"discoveredRoots\""))
            #expect(contents.contains("\"detector\" : \"FallbackDetector\""))
            #expect(contents.contains("\"isFallback\" : true"))
            #expect(contents.contains("\"sourceDirs\""))
        }
    }

    /// A folder with no manifest is the case the type count alone cannot explain, so the human
    /// report says it rather than leaving the detector name to be recognised.
    @Test func humanOutputSaysWhenNoBuildSystemWasRecognised() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("health.txt")
            var cmd = try CLITestSupport.parseAnalyze([
                "--source", dir.path, "--language", "swift", "--health",
                "--format", "human", "--output", output.path
            ])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("Project roots (1):"))
            #expect(contents.contains("FallbackDetector [swift]"))
            #expect(contents.contains("sources: ."))
            #expect(contents.contains("No build system recognised; analysed by file extension."))
        }
    }

    /// A manifest-scoped folder names the detector that claimed it and the directories it declared,
    /// and must not carry the "nothing was recognised" line.
    @Test func humanOutputNamesTheClaimingDetectorAndItsDirectories() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try "// swift-tools-version:6.0".write(
                to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            let sources = dir.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try CLITestSupport.writeSampleSwiftSource(in: sources)
            let output = dir.appendingPathComponent("health.txt")
            var cmd = try CLITestSupport.parseAnalyze([
                "--source", dir.path, "--language", "swift", "--health",
                "--format", "human", "--output", output.path
            ])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains(". — SwiftPackageManagerDetector [swift]"))
            #expect(contents.contains("sources: Sources"))
            #expect(!contents.contains("No build system recognised"))
        }
    }
}
