import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Inspect Enums Command")
struct InspectEnumsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseInspect(["--enums"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func listsCasesWithRawAndAssociatedValues() async throws {
        try await CLITestSupport.withTempDirectory { dir in
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
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("Suit"))
            #expect(contents.contains("\"rawValue\""))
            #expect(contents.contains("Payload"))
            #expect(contents.contains("\"associatedValues\""))
            #expect(contents.contains("String"))
        }
    }

    @Test func humanInventoryCarriesDocumentationOnTheEnumAndItsCases() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeDocumentedSwiftSource(in: dir)
            let output = dir.appendingPathComponent("enums.txt")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--enums",
                 "--format", "human", "--output", output.path])
            try await cmd.run()
            let lines = try String(contentsOf: output, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            #expect(lines.contains("  // A playing card's suit."))
            #expect(lines.contains("    // The red one."))
            // `spades` carries none, so its row is the last thing the report says about it.
            let index = try #require(lines.firstIndex { $0.hasPrefix("  - spades") })
            #expect(!lines[index + 1].contains("//"))
        }
    }

    @Test func noEnumsProducesEmptyList() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("enums.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--enums", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"enums\""))
            #expect(!contents.contains("\"cases\""))
        }
    }

    @Test func healthFieldIsPerfectOnCleanParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("enums.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--enums", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(contents.contains("\"score\" : 1"))
        }
    }
}
