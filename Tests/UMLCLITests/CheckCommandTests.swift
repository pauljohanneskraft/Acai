import ArgumentParser
import Foundation
import Testing
@testable import UMLCLI
import UMLConformance

@Suite("CLI: check command")
struct CheckCommandTests {

    private func parseCheck(_ arguments: [String]) throws -> UMLCommand.Check {
        let root = try UMLCommand.parseAsRoot(["check"] + arguments)
        return try #require(root as? UMLCommand.Check)
    }

    @Test func parsesRulesAndFlags() throws {
        let cmd = try parseCheck(["--source", "./", "--rules", "r.yml", "--no-fail", "--format", "json"])
        #expect(cmd.rules == "r.yml")
        #expect(cmd.noFail)
        #expect(cmd.format == .json)
    }

    @Test func parsesBaseline() throws {
        let cmd = try parseCheck(["--source", "./", "--rules", "r.yml", "--baseline", "last-release"])
        #expect(cmd.baseline == "last-release")
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

            var cmd = try parseCheck([
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
            _ = try parseCheck(["--rules", "r.yml"])
        }
    }

    @Test func lenientYAMLDecodesPartialRulesFile() throws {
        // Only a budgets section — forbidden/cycles omitted must not fail decoding.
        let rules = try ConformanceRules.load(yaml: """
        budgets:
          - metric: distance
            max: 0.5
        """)
        #expect(rules.budgets.count == 1)
        #expect(rules.forbidden.isEmpty)
        #expect(rules.cycles == nil)
        #expect(rules.budgets.first?.metric == .distance)
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

            var cmd = try parseCheck([
                "--source", src.path, "--language", "swift",
                "--rules", rulesURL.path, "--output", outURL.path
            ])
            // A real violation must surface as a non-zero ExitCode so CI fails the build.
            #expect(throws: ExitCode.self) { try cmd.run() }
            let report = try String(contentsOf: outURL, encoding: .utf8)
            #expect(report.contains("forbidden-dependency"))
        }
    }

    @Test func noFailSuppressesExitCode() throws {
        try CLITestSupport.withTempDirectory { dir in
            let src = dir.appendingPathComponent("src", isDirectory: true)
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "class A { var b: B }\nclass B {}\n"
                .write(to: src.appendingPathComponent("m.swift"), atomically: true, encoding: .utf8)
            let rulesURL = dir.appendingPathComponent("rules.yml")
            try "forbidden:\n  - from: { typeGlob: \"A\" }\n    to: { typeGlob: \"B\" }\n"
                .write(to: rulesURL, atomically: true, encoding: .utf8)

            var cmd = try parseCheck([
                "--source", src.path, "--language", "swift",
                "--rules", rulesURL.path, "--no-fail", "--output", dir.appendingPathComponent("o.txt").path
            ])
            // --no-fail reports but does not throw.
            try cmd.run()
        }
    }
}
