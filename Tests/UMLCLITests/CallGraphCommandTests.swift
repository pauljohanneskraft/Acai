import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml callgraph` and `uml call-cycles`: `--from`/`--source` validation, scope parsing, and
/// JSON output shape.
@Suite("CallGraph & CallCycles Commands")
struct CallGraphCommandTests {

    @Test func callgraphRequiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseCallGraph([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func callCyclesRejectsMalformedScope() throws {
        #expect {
            _ = try CLITestSupport.parseCallCycles(
                ["--source", CLITestSupport.nonexistentPath(), "--scope", "bogus"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("type:Name")
        }
    }

    @Test func callgraphEmitsMetricsJSON() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("callgraph.json")
            var cmd = try CLITestSupport.parseCallGraph(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"coverage\""))
            #expect(contents.contains("\"fanIn\""))
            #expect(contents.contains("\"fanOut\""))
        }
    }

    @Test func callCyclesReportsNoneForAcyclicSource() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("cycles.json")
            var cmd = try CLITestSupport.parseCallCycles(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            // Sample source (Service → Repository) has no call cycle, so no failure exit.
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("["))
        }
    }
}
