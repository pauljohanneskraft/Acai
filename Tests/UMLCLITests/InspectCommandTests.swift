import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml inspect`: `--from`/`--source` validation, selector + member filtering, and that every
/// emitted row carries a `file:line` jump target.
@Suite("Inspect Command")
struct InspectCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseInspect([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func emitsTypesAndMembersWithLocations() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"qualifiedName\""))
            #expect(contents.contains("Service"))
            #expect(contents.contains("\"members\""))
            // Precise jump targets: file path + line for each row.
            #expect(contents.contains("\"filePath\""))
            #expect(contents.contains("\"line\""))
        }
    }

    @Test func memberFilterNarrowsToMatchingTypes() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            // No member has 5+ parameters, so the active member filter drops every type.
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift",
                 "--member-kind", "method", "--min-parameters", "5", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("["))
            #expect(!contents.contains("\"qualifiedName\""))
        }
    }
}
