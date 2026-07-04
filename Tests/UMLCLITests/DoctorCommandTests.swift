import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml doctor`: `--from`/`--source` validation and the parse-health JSON report (a clean
/// source scores 1.0).
@Suite("Doctor Command")
struct DoctorCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseDoctor([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func cleanSourceScoresPerfect() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("doctor.json")
            var cmd = try CLITestSupport.parseDoctor(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"score\" : 1"))
            #expect(contents.contains("\"diagnosticCount\" : 0"))
            #expect(contents.contains("\"typeCount\""))
        }
    }
}
