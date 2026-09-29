import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

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

    @Test func nonexistentSourceThrows() async throws {
        var cmd = try CLITestSupport.parseMetrics(["--source", CLITestSupport.nonexistentPath()])
        await #expect {
            try await cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains("Source directory does not exist:")
        }
    }

    @Test func writesMetricsJSONToOutputFile() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("metrics.json")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--output", output.path]
            )
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.hasPrefix("{"))
            #expect(contents.contains("counts"))
            #expect(contents.contains("totalTypes"))
        }
    }

    @Test func healthFieldIsPerfectOnCleanParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("metrics.json")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
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
            let output = dir.appendingPathComponent("metrics.json")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(!contents.contains("\"score\" : 1"))
        }
    }

    /// `Sample.swift` declares `Service` on lines 1–6 and `Repository` on lines 8–10, with a blank
    /// line 7 between them — so the pinned codebase total is 9, not the file's 10 lines (#330).
    @Test func jsonCarriesLinesOfCodeAtEveryScope() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("metrics.json")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let root = try JSONSerialization.jsonObject(
                with: Data(contentsOf: output)) as? [String: Any]
            let metrics = root?["metrics"] as? [String: Any]
            #expect((metrics?["counts"] as? [String: Any])?["linesOfCode"] as? Int == 9)
            let types = metrics?["types"] as? [[String: Any]]
            #expect(types?.first { $0["name"] as? String == "Service" }?["linesOfCode"] as? Int == 6)
            #expect(types?.first { $0["name"] as? String == "Repository" }?["linesOfCode"] as? Int == 3)
            let modules = metrics?["modules"] as? [[String: Any]]
            #expect(modules?.compactMap { $0["linesOfCode"] as? Int }.reduce(0, +) == 9)
        }
    }

    @Test func humanReportPrintsTheLinesColumnAndTotal() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("metrics.txt")
            var cmd = try CLITestSupport.parseMetrics(
                ["--source", dir.path, "--language", "swift", "--format", "human",
                 "--sort", "linesOfCode", "--output", output.path])
            try await cmd.run()
            let lines = try String(contentsOf: output, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.first?.contains("Lines: 9") == true)
            let header = try #require(lines.first { $0.hasPrefix("TYPE") })
            #expect(header.contains("loc"))
            // Ranked by linesOfCode, so the 6-line `Service` precedes the 3-line `Repository`.
            let ranked = lines.filter { $0.hasPrefix("Service") || $0.hasPrefix("Repository") }
            #expect(ranked.first?.hasPrefix("Service") == true)
            #expect(try #require(ranked.first { $0.hasPrefix("Service") }).hasSuffix("6"))
            // No row may exceed the report's 120-column budget now that a column was added.
            #expect(lines.allSatisfy { $0.count <= 120 })
        }
    }
}
