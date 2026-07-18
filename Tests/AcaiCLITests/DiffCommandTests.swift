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

    @Test func runReportsAddedAndRemovedEdges() throws {
        try CLITestSupport.withTempDirectory { dir in
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
            try cmd.run()

            let report = try String(contentsOf: outURL, encoding: .utf8)
            #expect(report.contains("inheritance removed"))
        }
    }
}
