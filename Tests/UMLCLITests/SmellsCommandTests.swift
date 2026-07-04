import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml smells`: `--from`/`--source` validation and that a smelly source yields ranked
/// `smell` findings with `file:line` in the JSON output.
@Suite("Smells Command")
struct SmellsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseSmells([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func reportsLongParameterListSmell() throws {
        try CLITestSupport.withTempDirectory { dir in
            let source = """
            class Widget {
                func configure(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) {}
            }
            """
            try source.write(
                to: dir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("smells.json")
            var cmd = try CLITestSupport.parseSmells(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"ruleKind\" : \"smell\""))
            #expect(contents.contains("maxParameters"))
            #expect(contents.contains("\"filePath\""))
        }
    }
}
