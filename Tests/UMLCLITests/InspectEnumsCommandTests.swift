import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml inspect --enums` (the merged former `enums`): the enum-case inventory (cases, raw
/// values, associated values) with locations, and an empty array when there are no enums.
@Suite("Inspect Enums Command")
struct InspectEnumsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseInspect(["--enums"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func listsCasesWithRawAndAssociatedValues() throws {
        try CLITestSupport.withTempDirectory { dir in
            let source = """
            enum Suit: String {
                case hearts = "H"
                case spades = "S"
            }

            enum Payload {
                case text(String)
                case number(count: Int)
            }
            """
            try source.write(
                to: dir.appendingPathComponent("Enums.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("enums.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--enums", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("Suit"))
            #expect(contents.contains("\"rawValue\""))
            #expect(contents.contains("Payload"))
            #expect(contents.contains("\"associatedValues\""))
            #expect(contents.contains("String"))
        }
    }

    @Test func noEnumsProducesEmptyArray() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("enums.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--enums", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("["))
            #expect(!contents.contains("\"cases\""))
        }
    }
}
