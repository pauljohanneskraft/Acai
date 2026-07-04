import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Covers `uml impact`: `--from`/`--source` validation and the blast-radius JSON for a known type.
@Suite("Impact Command")
struct ImpactCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseImpact(["SomeType"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func reportsDependentsForKnownType() throws {
        try CLITestSupport.withTempDirectory { dir in
            // Service depends on Repository, so Repository's blast radius includes Service.
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("impact.json")
            var cmd = try CLITestSupport.parseImpact(
                ["Repository", "--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"found\" : true"))
            #expect(contents.contains("Service"))
            #expect(contents.contains("\"blastRadius\""))
        }
    }
}
