import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Inspect Command")
struct InspectCommandTests {

    @Test func requiresFromOrSource() throws {
        #expect {
            _ = try CLITestSupport.parseInspect([])
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    @Test func emitsTypesAndMembersWithLocations() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"qualifiedName\""))
            #expect(contents.contains("Service"))
            #expect(contents.contains("\"members\""))
            #expect(contents.contains("\"filePath\""))
            #expect(contents.contains("\"line\""))
        }
    }

    @Test func humanReportCarriesDocumentationAsCommentLines() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeDocumentedSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.txt")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--format", "human", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("  // Stores and retrieves orders."))
            #expect(contents.contains("    // Writes the order to disk."))
        }
    }

    @Test func humanReportLeavesAnUndocumentedDeclarationWithoutAPlaceholder() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeDocumentedSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.txt")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--format", "human", "--output", output.path])
            try await cmd.run()
            let lines = try String(contentsOf: output, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            // The undocumented type's row is followed straight by its member, and that member's row
            // by the next line of structure — no blank comment, no "no documentation" stand-in.
            let index = try #require(lines.firstIndex { $0.hasPrefix("Undocumented ") })
            #expect(lines[index + 1].hasPrefix("  - run"))
            #expect(!lines[index + 2].contains("//"))
        }
    }

    @Test func jsonReportCarriesDocumentationOnTypesAndMembers() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeDocumentedSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"documentation\""))
            #expect(contents.contains("Stores and retrieves orders."))
            #expect(contents.contains("Writes the order to disk."))
        }
    }

    @Test func memberFilterNarrowsToMatchingTypes() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            // No member has 5+ parameters, so the active member filter drops every type.
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift",
                 "--member-kind", "method", "--min-parameters", "5", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"types\""))
            #expect(!contents.contains("\"qualifiedName\""))
        }
    }

    @Test func healthFieldIsPerfectOnCleanParse() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("inspect.json")
            var cmd = try CLITestSupport.parseInspect(
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
            let output = dir.appendingPathComponent("inspect.json")
            var cmd = try CLITestSupport.parseInspect(
                ["--source", dir.path, "--language", "swift", "--output", output.path])
            try await cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"health\""))
            #expect(!contents.contains("\"score\" : 1"))
        }
    }
}
