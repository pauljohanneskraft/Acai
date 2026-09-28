import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("CLI: diff command")
struct DiffCommandTests {

    private func parseDiff(_ arguments: [String]) throws -> AcaiCommand.Diff {
        let root = try AcaiCommand.parseAsRoot(["diff"] + arguments)
        return try #require(root as? AcaiCommand.Diff)
    }

    @Test func acceptsTwoPositionalArtifacts() throws {
        let cmd = try parseDiff(["old.json", "new.json"])
        #expect(cmd.old == "old.json")
        #expect(cmd.new == "new.json")
        #expect(cmd.format == .human)
    }

    @Test func acceptsSourceDirsForBothSides() throws {
        let cmd = try parseDiff(["--source-old", "./a", "--source-new", "./b", "--format", "json"])
        #expect(cmd.sourceOld == "./a")
        #expect(cmd.sourceNew == "./b")
        #expect(cmd.format == .json)
    }

    @Test func rejectsMissingSide() {
        #expect(throws: (any Error).self) {
            _ = try parseDiff(["old.json"])
        }
    }

    @Test func rejectsBothRefAndSourceOnOneSide() {
        #expect(throws: (any Error).self) {
            _ = try parseDiff(["old.json", "new.json", "--source-old", "./a"])
        }
    }

    @Test func runReportsAddedAndRemovedEdges() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let before = dir.appendingPathComponent("before", isDirectory: true)
            let after = dir.appendingPathComponent("after", isDirectory: true)
            try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: after, withIntermediateDirectories: true)
            try "class User: Account {}\nclass Account {}\n"
                .write(to: before.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)
            try "class User {}\nclass Account {}\n"
                .write(to: after.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)

            let outURL = dir.appendingPathComponent("out.txt")
            var cmd = try parseDiff([
                "--source-old", before.path, "--source-new", after.path,
                "--language", "swift", "--output", outURL.path
            ])
            try await cmd.run()

            let report = try String(contentsOf: outURL, encoding: .utf8)
            #expect(report.contains("inheritance removed"))
        }
    }

    @Test func healthFieldIsPerfectOnCleanParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let before = dir.appendingPathComponent("before", isDirectory: true)
            let after = dir.appendingPathComponent("after", isDirectory: true)
            try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: after, withIntermediateDirectories: true)
            try CLITestSupport.writeSampleSwiftSource(in: before)
            try CLITestSupport.writeSampleSwiftSource(in: after)

            let outURL = dir.appendingPathComponent("out.json")
            var cmd = try parseDiff([
                "--source-old", before.path, "--source-new", after.path,
                "--language", "swift", "--format", "json", "--output", outURL.path
            ])
            try await cmd.run()
            let contents = try String(contentsOf: outURL, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(contents.contains("\"score\" : 1"))
            #expect(contents.contains("\"diagnosticCount\" : 0"))
        }
    }

    @Test func healthFieldReflectsLowTrustParseOnEitherSide() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let before = dir.appendingPathComponent("before", isDirectory: true)
            let after = dir.appendingPathComponent("after", isDirectory: true)
            try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: after, withIntermediateDirectories: true)
            try CLITestSupport.writeSampleSwiftSource(in: before)
            try CLITestSupport.writeLowTrustSwiftSource(in: after)

            let outURL = dir.appendingPathComponent("out.json")
            var cmd = try parseDiff([
                "--source-old", before.path, "--source-new", after.path,
                "--language", "swift", "--format", "json", "--output", outURL.path
            ])
            try await cmd.run()
            let contents = try String(contentsOf: outURL, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(!contents.contains("\"score\" : 1"))
        }
    }

    // MARK: - Generated scope

    /// Dart is the fixture language because its `LanguageConfiguration` carries a
    /// `generatedCodeFilter` (`.g.dart` and friends); Swift's does not.
    private func writeDartSides(in dir: URL, generatedTypeAddedInNew: String) throws -> (URL, URL) {
        let before = dir.appendingPathComponent("before", isDirectory: true)
        let after = dir.appendingPathComponent("after", isDirectory: true)
        for side in [before, after] {
            try FileManager.default.createDirectory(at: side, withIntermediateDirectories: true)
            try "class Model {}\n".write(
                to: side.appendingPathComponent("model.dart"), atomically: true, encoding: .utf8)
        }
        try "class ModelAdapter {}\n".write(
            to: before.appendingPathComponent("model.g.dart"), atomically: true, encoding: .utf8)
        try "class ModelAdapter {}\nclass \(generatedTypeAddedInNew) {}\n".write(
            to: after.appendingPathComponent("model.g.dart"), atomically: true, encoding: .utf8)
        return (before, after)
    }

    private func diffJSON(_ arguments: [String], in dir: URL) async throws -> String {
        let outURL = dir.appendingPathComponent("out-\(UUID().uuidString).json")
        var cmd = try parseDiff(arguments + ["--format", "json", "--output", outURL.path])
        try await cmd.run()
        return try String(contentsOf: outURL, encoding: .utf8)
    }

    @Test func generatedOnlyChangeIsInvisibleByDefault() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let (before, after) = try writeDartSides(in: dir, generatedTypeAddedInNew: "ExtraAdapter")
            let contents = try await diffJSON(
                ["--source-old", before.path, "--source-new", after.path, "--language", "dart"], in: dir)
            #expect(!contents.contains("ExtraAdapter"))
        }
    }

    @Test func generatedOnlyChangeSurfacesWithIncludeGenerated() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let (before, after) = try writeDartSides(in: dir, generatedTypeAddedInNew: "ExtraAdapter")
            let contents = try await diffJSON(
                ["--source-old", before.path, "--source-new", after.path,
                 "--language", "dart", "--include-generated"], in: dir)
            #expect(contents.contains("ExtraAdapter"))
        }
    }

    /// The filter runs on both sides, so a type generated on *both* revisions is never reported as
    /// removed (old side filtered, new side not) or added.
    @Test func filteringNeverAddsOrRemovesATypeByItself() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            let (before, after) = try writeDartSides(in: dir, generatedTypeAddedInNew: "ExtraAdapter")
            let contents = try await diffJSON(
                ["--source-old", before.path, "--source-new", after.path, "--language", "dart"], in: dir)
            #expect(!contents.contains("ModelAdapter"))
        }
    }

    @Test func parsesIncludeGeneratedFlag() throws {
        #expect(try parseDiff(["old.json", "new.json"]).generatedScope.includeGenerated == false)
        #expect(try parseDiff(["old.json", "new.json", "--include-generated"])
            .generatedScope.includeGenerated == true)
    }
}
