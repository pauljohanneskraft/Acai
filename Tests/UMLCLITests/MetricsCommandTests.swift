import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml metrics`: its `--from`/`--source` validation and the on-the-fly analysis →
/// JSON-metrics output path.
@Suite("Metrics Command")
struct MetricsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseMetrics([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func rejectsBothFromAndSource() throws {
        #expect {
            _ = try CLITestSupport.parseMetrics(["--from", "a", "--source", "b"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("not both")
        }
    }

    @Test func nonexistentSourceThrows() throws {
        var cmd = try CLITestSupport.parseMetrics(["--source", CLITestSupport.nonexistentPath()])
        #expect {
            try cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains("Source directory does not exist:")
        }
    }

    @Test func writesMetricsJSONToOutputFile() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("metrics.json")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--output", output.path]
            )
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            // Valid JSON object carrying the metrics sections.
            #expect(contents.hasPrefix("{"))
            #expect(contents.contains("counts"))
            #expect(contents.contains("totalTypes"))
        }
    }
}
