import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI

/// Drives `UMLCommand.Diagram.run()` for the error and success paths that only surface after
/// parsing (entry-point/`--map`/scope/YAML parsing, on-the-fly analysis, file output).
@Suite("Diagram Command Run")
struct DiagramCommandRunTests {

    /// Asserts that running `diagram` with `arguments` throws an error whose message contains
    /// `expected`.
    private func expectRunError(_ arguments: [String], contains expected: String) throws {
        var cmd = try CLITestSupport.parseDiagram(arguments)
        #expect {
            try cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains(expected)
        }
    }

    @Test func nonexistentSourceThrows() throws {
        try expectRunError(
            ["--source", CLITestSupport.nonexistentPath()],
            contains: "Source directory does not exist:"
        )
    }

    @Test func malformedSequenceEntryPointThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            // A leading/trailing dot is malformed; a bare name (no dot) is now a valid form — it
            // denotes a top-level function entry point.
            for bad in [".method", "Type."] {
                try expectRunError(
                    ["--source", dir.path, "--sequence-from", bad],
                    contains: "--sequence-from must be"
                )
            }
        }
    }

    @Test func malformedMapThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            try expectRunError(
                ["--source", dir.path, "--sequence-from", "Service.run", "--map", "NoEquals"],
                contains: "--map must be in the form"
            )
        }
    }

    @Test func malformedCallGraphScopeThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            try expectRunError(
                ["--source", dir.path, "--call-graph", "--call-graph-scope", "bogus:X"],
                contains: "--call-graph-scope must start with"
            )
            try expectRunError(
                ["--source", dir.path, "--call-graph", "--call-graph-scope", "type:"],
                contains: "--call-graph-scope must be"
            )
        }
    }

    @Test func malformedYAMLConfigThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            // A YAML sequence (list) instead of a top-level mapping.
            let configURL = dir.appendingPathComponent("config.yml")
            try "- a\n- b\n".write(to: configURL, atomically: true, encoding: .utf8)
            try expectRunError(
                ["--source", dir.path, "--config", configURL.path],
                contains: "Invalid YAML configuration"
            )
        }
    }

    @Test func unknownStoredAnalysisThrows() throws {
        try expectRunError(
            ["--from", "definitely-not-a-stored-analysis-\(UUID().uuidString)"],
            contains: "Could not find analysis"
        )
    }

    @Test func writesDotToOutputFile() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("diagram.dot")
            var cmd = try CLITestSupport.parseDiagram(
                ["--source", dir.path, "--language", "swift", "--output", output.path]
            )
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("digraph"))
            #expect(contents.contains("Service"))
        }
    }

    @Test func minAccessHidesLowerVisibilityMembers() throws {
        try CLITestSupport.withTempDirectory { dir in
            let source = """
            public class Widget {
                public func show() {}
                private func helper() {}
            }
            """
            try source.write(to: dir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("diagram.dot")
            var cmd = try CLITestSupport.parseDiagram(
                ["--source", dir.path, "--language", "swift", "--min-access", "public", "--output", output.path]
            )
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("show"))
            #expect(!contents.contains("helper"))
        }
    }

    @Test func minAccessFiltersMiddleTiers() throws {
        try CLITestSupport.withTempDirectory { dir in
            // Exercises the contested package/internal boundary: `package` outranks `internal`, so
            // `--min-access packagePrivate` keeps the package member and drops the internal one.
            let source = """
            public class Widget {
                public func shown() {}
                package func packaged() {}
                internal func hidden() {}
            }
            """
            try source.write(to: dir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("diagram.dot")
            var cmd = try CLITestSupport.parseDiagram(
                ["--source", dir.path, "--language", "swift",
                 "--min-access", "packagePrivate", "--output", output.path]
            )
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("shown"))
            #expect(contents.contains("packaged"))
            #expect(!contents.contains("hidden"))
        }
    }

    @Test func writesMermaidToOutputFile() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("diagram.mmd")
            var cmd = try CLITestSupport.parseDiagram(
                ["--source", dir.path, "--language", "swift", "--format", "mermaid", "--output", output.path]
            )
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("classDiagram"))
        }
    }

    @Test func untraceableSequenceEntryPointThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            // A real type/method split, but no such method exists to trace.
            try expectRunError(
                ["--source", dir.path, "--sequence-from", "Service.missing"],
                contains: "No calls could be traced"
            )
        }
    }

    @Test func callGraphWithNoResolvableCallsThrows() throws {
        try CLITestSupport.withTempDirectory { dir in
            // A lone type with no call sites yields a call graph with no edges.
            try "class Lonely { func idle() {} }".write(
                to: dir.appendingPathComponent("Lonely.swift"), atomically: true, encoding: .utf8
            )
            try expectRunError(
                ["--source", dir.path, "--call-graph"],
                contains: "No resolvable calls found"
            )
        }
    }
}
