import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml enums`: `--from`/`--source` validation and the enum-case inventory (cases, raw values,
/// associated values) with locations.
@Suite("Enums Command")
struct EnumsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseEnums([])
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
            var cmd = try CLITestSupport.parseEnums(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
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
            var cmd = try CLITestSupport.parseEnums(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("["))
            #expect(!contents.contains("\"cases\""))
        }
    }
}
