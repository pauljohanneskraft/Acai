import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml deadcode`: `--from`/`--source` validation and that the JSON report carries coverage +
/// candidates.
@Suite("DeadCode Command")
struct DeadCodeCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseDeadCode([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func reportsCandidatesAndCoverage() throws {
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
            var cmd = try CLITestSupport.parseDeadCode(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"coverage\""))
            #expect(contents.contains("\"candidates\""))
            #expect(contents.contains("Service.helper"))
        }
    }
}
