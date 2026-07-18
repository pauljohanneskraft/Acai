import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

/// Covers `acai callgraph` and its three modes (metrics / cycles / deadcode, the merged former
/// `callgraph` + `call-cycles` + `deadcode`): `--from`/`--source` validation, scope parsing, and the
/// JSON output shape of each mode.
@Suite("CallGraph Command")
struct CallGraphCommandTests {

    @Test func callgraphRequiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseCallGraph([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func rejectsMalformedScope() throws {
        #expect {
            _ = try CLITestSupport.parseCallGraph(
                ["--source", CLITestSupport.nonexistentPath(), "--mode", "cycles", "--scope", "bogus"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("type:Name")
        }
    }

    @Test func metricsModeEmitsMetricsJSON() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("callgraph.json")
            // metrics is the default mode.
            var cmd = try CLITestSupport.parseCallGraph(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"coverage\""))
            #expect(contents.contains("\"fanIn\""))
            #expect(contents.contains("\"fanOut\""))
        }
    }

    @Test func cyclesModeReportsNoneForAcyclicSource() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("cycles.json")
            var cmd = try CLITestSupport.parseCallGraph(
                ["--source", dir.path, "--language", "swift", "--mode", "cycles", "--output", output.path])
            // Sample source (Service → Repository) has no call cycle, so no failure exit.
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("["))
        }
    }

    @Test func deadcodeModeReportsCandidatesAndCoverage() throws {
        try CLITestSupport.withTempDirectory { dir in
            // `helper()` is private and never called → a dead-code candidate.
            let source = """
            public class Service {
                private func helper() {}
            }
            """
            try source.write(
                to: dir.appendingPathComponent("Service.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("deadcode.json")
            var cmd = try CLITestSupport.parseCallGraph(
                ["--source", dir.path, "--language", "swift", "--mode", "deadcode", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"coverage\""))
            #expect(contents.contains("\"candidates\""))
            #expect(contents.contains("Service.helper"))
        }
    }
}
