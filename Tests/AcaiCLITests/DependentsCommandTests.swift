import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Dependents Command")
struct DependentsCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseDependents(["SomeType"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func reportsDependentsForKnownType() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            // Service depends on Repository, so Repository's blast radius includes Service.
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("dependents.json")
            var cmd = try CLITestSupport.parseDependents(
                ["Repository", "--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"found\" : true"))
            #expect(contents.contains("Service"))
            #expect(contents.contains("\"blastRadius\""))
        }
    }

    @Test func healthFieldIsPerfectOnCleanParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("dependents.json")
            var cmd = try CLITestSupport.parseDependents(
                ["Repository", "--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(contents.contains("\"score\" : 1"))
            #expect(contents.contains("\"diagnosticCount\" : 0"))
        }
    }

    @Test func healthFieldReflectsLowTrustParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeLowTrustSwiftSource(in: dir)
            let output = dir.appendingPathComponent("dependents.json")
            var cmd = try CLITestSupport.parseDependents(
                ["Broken", "--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(!contents.contains("\"score\" : 1"))
        }
    }

    @Test func deprecatedImpactAliasReportsTheSameDependents() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("impact.json")
            var cmd = try CLITestSupport.parseImpactAlias(
                ["Repository", "--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"found\" : true"))
            #expect(contents.contains("Service"))
            #expect(contents.contains("\"blastRadius\""))
        }
    }

    @Test func deprecatedImpactAliasValidatesItsSource() throws {
        #expect {
            _ = try CLITestSupport.parseImpactAlias(["SomeType"])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func deprecatedImpactAliasIsHiddenFromHelp() {
        let help = AcaiCommand.helpMessage()
        #expect(help.contains("dependents"))
        #expect(!help.contains("impact"))
    }
}
