import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI
import AcaiQuality

/// Covers `acai quality` — the merged code-quality check + smells: rule/flag parsing, baseline drift,
/// the pass/fail gate, `--explore` (non-failing) ranking, the built-in default smell budgets when no
/// rules file is given, and lenient/robust YAML rule-file decoding.
@Suite("CLI: quality command")
struct QualityCommandTests {

    private func parseQuality(_ arguments: [String]) throws -> AcaiCommand.Quality {
        try CLITestSupport.parseQuality(arguments)
    }

    @Test func parsesRulesAndFlags() throws {
        let cmd = try parseQuality(["--source", "./", "--rules", "r.yml", "--explore", "--format", "json"])
        #expect(cmd.rules == "r.yml")
        #expect(cmd.explore)
        #expect(cmd.format == .json)
    }

    @Test func parsesBaseline() throws {
        let cmd = try parseQuality(["--source", "./", "--rules", "r.yml", "--baseline", "last-release"])
        #expect(cmd.baseline == "last-release")
    }

    @Test func rulesAreOptional() throws {
        // Omitting --rules is valid: the built-in curated smell budgets are used.
        let cmd = try parseQuality(["--source", "./"])
        #expect(cmd.rules == nil)
    }

    @Test func baselineDriftAppearsInReport() throws {
        try CLITestSupport.withTempDirectory { dir in
            let src = dir.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "class A {}\nclass B {}\nclass C { var a: A }\n"
                .write(to: src.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)
            // Baseline has only an empty type set; the current source adds types/edges → drift.
            let baseURL = dir.appendingPathComponent("base.json")
            let baseJSON = """
            {"metadata":{"filePaths":[],"parseDiagnostics":[],"sourceLanguage":"swift"},\
            "freestandingFunctions":[],"globalVariables":[],"relationships":[],"types":[]}
            """
            try baseJSON.write(to: baseURL, atomically: true, encoding: .utf8)
            let rulesURL = dir.appendingPathComponent("rules.yml")
            try "budgets:\n  - metric: distance\n    max: 1.0\n"
                .write(to: rulesURL, atomically: true, encoding: .utf8)
            let outURL = dir.appendingPathComponent("out.txt")

            var cmd = try parseQuality([
                "--source", src.path, "--language", "swift",
                "--rules", rulesURL.path, "--baseline", baseURL.path, "--output", outURL.path
            ])
            try cmd.run()
            let report = try String(contentsOf: outURL, encoding: .utf8)
            #expect(report.contains("Drift since baseline"))
        }
    }

    @Test func requiresArtifactSource() {
        #expect(throws: (any Error).self) {
            _ = try parseQuality(["--rules", "r.yml"])
        }
    }

    @Test func defaultBudgetsFlagSmellsInExploreMode() throws {
        try CLITestSupport.withTempDirectory { dir in
            let source = """
            class Widget {
                func configure(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) {}
            }
            """
            try source.write(
                to: dir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
            let output = dir.appendingPathComponent("quality.json")
            // No --rules: the built-in smell budgets apply. --explore so the breach doesn't fail exit.
            var cmd = try parseQuality(
                ["--source", dir.path, "--language", "swift", "--explore", "--format", "json", "--output", output.path])
            try cmd.run()
            let contents = try String(contentsOf: output, encoding: .utf8)
            #expect(contents.contains("\"ruleKind\" : \"budget\""))
            #expect(contents.contains("maxParameters"))
            #expect(contents.contains("\"filePath\""))
        }
    }

    @Test func lenientYAMLDecodesPartialRulesFile() throws {
        // Only a budgets section — forbidden/cycles omitted must not fail decoding.
        let rules = try QualityRules.load(yaml: """
        budgets:
          - metric: distance
            max: 0.5
        """)
        #expect(rules.budgets.count == 1)
        #expect(rules.forbidden.isEmpty)
        #expect(rules.cycles == nil)
        #expect(rules.budgets.first?.metric == .distance)
    }

    @Test func schemaMismatchSurfacesReadableCause() {
        // `budgets` must be a list; a scalar is a type mismatch the decoder can locate.
        #expect {
            _ = try QualityRules.load(yaml: "budgets: 5\n")
        } throws: { error in
            let message = "\(error)"
            // The cause is preserved (the offending key is named) without the raw `Context(...)` dump.
            return message.contains("Invalid rules file:")
                && message.contains("budgets")
                && !message.contains("Context(")
        }
    }

    @Test func malformedYAMLStillSurfacesAsValidationError() {
        // A syntax error (unterminated flow sequence) goes through the non-decoding branch.
        #expect {
            _ = try QualityRules.load(yaml: "budgets: [unterminated\n")
        } throws: { error in
            "\(error)".contains("Invalid rules file:")
        }
    }

    @Test func failingCheckThrowsNonZeroExit() throws {
        try CLITestSupport.withTempDirectory { dir in
            let src = dir.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "class A { var b: B }\nclass B {}\n"
                .write(to: src.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)
            let rulesURL = dir.appendingPathComponent("rules.yml")
            try "forbidden:\n  - from: { typeGlob: \"A\" }\n    to: { typeGlob: \"B\" }\n"
                .write(to: rulesURL, atomically: true, encoding: .utf8)
            let outURL = dir.appendingPathComponent("out.txt")

            var cmd = try parseQuality([
                "--source", src.path, "--language", "swift",
                "--rules", rulesURL.path, "--output", outURL.path
            ])
            // A real violation must surface as a non-zero ExitCode so CI fails the build.
            #expect(throws: ExitCode.self) { try cmd.run() }
            let report = try String(contentsOf: outURL, encoding: .utf8)
            #expect(report.contains("forbidden-dependency"))
        }
    }

    @Test func exploreSuppressesExitCode() throws {
        try CLITestSupport.withTempDirectory { dir in
            let src = dir.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "class A { var b: B }\nclass B {}\n"
                .write(to: src.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)
            let rulesURL = dir.appendingPathComponent("rules.yml")
            try "forbidden:\n  - from: { typeGlob: \"A\" }\n    to: { typeGlob: \"B\" }\n"
                .write(to: rulesURL, atomically: true, encoding: .utf8)

            var cmd = try parseQuality([
                "--source", src.path, "--language", "swift",
                "--rules", rulesURL.path, "--explore", "--output", dir.appendingPathComponent("o.txt").path
            ])
            // --explore reports but does not throw.
            try cmd.run()
        }
    }
}
