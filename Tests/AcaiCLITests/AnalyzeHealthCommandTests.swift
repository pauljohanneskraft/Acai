import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

/// Covers `acai analyze --health` (the merged former `doctor`): the parse-health JSON report, where a
/// clean source scores 1.0 with zero diagnostics.
@Suite("Analyze Health Command")
struct AnalyzeHealthCommandTests {

    @Test func cleanSourceScoresPerfect() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("health.json")
            var cmd = try CLITestSupport.parseAnalyze(
                ["--source", dir.path, "--language", "swift", "--health", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"score\" : 1"))
            #expect(contents.contains("\"diagnosticCount\" : 0"))
            #expect(contents.contains("\"typeCount\""))
        }
    }
}
