import Foundation
import Testing
import AcaiQuality
@testable import AcaiCLI

@Suite("CLI: rules init")
struct RulesInitCommandTests {

    @Test func generatesADraftThatReloadsViaTheChecker() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("quality.yml")

            var cmd = try CLITestSupport.parseRulesInit(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try cmd.run()

            let yaml = try String(contentsOf: output, encoding: .utf8)
            #expect(yaml.contains("cycles:"))
            #expect(yaml.contains("budgets:"))

            // The active sections must re-parse — a draft the checker can immediately consume.
            let reloaded = try QualityRules.load(contentsOf: output.path)
            #expect(reloaded.cycles?.scope == .modules)
            #expect(!reloaded.budgets.isEmpty)
        }
    }
}
