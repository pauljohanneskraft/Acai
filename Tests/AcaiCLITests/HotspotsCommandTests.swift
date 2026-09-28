// The fixture shells out to real `git`, and `hotspots` itself is macOS-only.
#if os(macOS)
import ArgumentParser
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Hotspots Command")
struct HotspotsCommandTests {

    /// A repository whose churn and complexity are both known: `Hot.swift` is the only file above
    /// both medians (churn 3 / complexity > 1, against `Mid.swift`'s 2 / 1 and `Cold.swift`'s 1 / 1).
    /// The parentless root commit contributes no touches, so `Seed.md` carries the initial commit
    /// and never appears in the churn map.
    private struct Fixture {
        let directory: URL

        func build() throws {
            try git(["init", "-q", "--initial-branch=main"])
            try write("Seed.md", "seed\n")
            try commit("seed")

            try write("Cold.swift", "class Cold {\n    func value() -> Int { 1 }\n}\n")
            try write("Mid.swift", "class Mid {\n    func value() -> Int { 2 }\n}\n")
            try write("Hot.swift", hotSource(returning: 0))
            try commit("add sources")

            try write("Mid.swift", "class Mid {\n    func value() -> Int { 3 }\n}\n")
            try write("Hot.swift", hotSource(returning: 1))
            try commit("edit mid and hot")

            try write("Hot.swift", hotSource(returning: 2))
            try commit("edit hot again")
        }

        /// Branching the Swift parser measures as cyclomatic complexity, so `Hot.swift` clears the
        /// complexity median the two trivial files set.
        private func hotSource(returning seed: Int) -> String {
            """
            class Hot {
                func classify(_ value: Int) -> String {
                    if value < \(seed) { return "low" }
                    if value == \(seed) { return "equal" }
                    if value > 10 { return "high" }
                    if value.isMultiple(of: 2) { return "even" }
                    return "odd"
                }
            }

            """
        }

        private func write(_ name: String, _ contents: String) throws {
            try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        private func commit(_ message: String) throws {
            try git(["add", "-A"])
            try git(["commit", "-q", "-m", message])
        }

        private func git(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            // The runner carries a global git config CI rewrites remotes in; a fixture must not
            // inherit it.
            process.environment = [
                "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
                "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
                "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
        }
    }

    private func withFixtureRepository<T>(_ body: (URL) async throws -> T) async throws -> T {
        try await CLITestSupport.withTempDirectory { directory in
            try Fixture(directory: directory).build()
            return try await body(directory)
        }
    }

    @Test("The file that is both most-changed and most-complex is the ranked hotspot")
    func ranksTheChurnedComplexFile() async throws {
        try await withFixtureRepository { directory in
            let output = directory.appendingPathComponent("hotspots.json")
            var command = try CLITestSupport.parseHotspots(
                ["--source", directory.path, "--language", "swift", "--format", "json",
                 "--output", output.path])
            try await command.run()

            let report = try JSONDecoder().decode(Report.self, from: try Data(contentsOf: output))
            #expect(report.hotspots.map(\.path) == ["Hot.swift"])
            let hot = try #require(report.hotspots.first)
            #expect(hot.churn == 3)
            #expect(hot.complexity > 1)
            #expect(hot.score == hot.churn * hot.complexity)
            #expect(report.commitWindow == 50)
            #expect(report.filesScored == 3)
            #expect(report.hotspotCount == 1)
        }
    }

    @Test("The human report names the hotspot and the window it was measured over")
    func humanReportNamesTheHotspot() async throws {
        try await withFixtureRepository { directory in
            let output = directory.appendingPathComponent("hotspots.txt")
            var command = try CLITestSupport.parseHotspots(
                ["--source", directory.path, "--language", "swift", "--commits", "10",
                 "--output", output.path])
            try await command.run()

            let text = try String(contentsOf: output, encoding: .utf8)
            #expect(text.contains("Hot.swift"))
            #expect(text.contains("last 10 commits"))
            #expect(!text.contains("Cold.swift"))
        }
    }

    @Test("--top limits the ranked list")
    func topLimitsTheList() async throws {
        try await withFixtureRepository { directory in
            let output = directory.appendingPathComponent("hotspots.json")
            var command = try CLITestSupport.parseHotspots(
                ["--source", directory.path, "--language", "swift", "--format", "json",
                 "--top", "1", "--output", output.path])
            try await command.run()

            let report = try JSONDecoder().decode(Report.self, from: try Data(contentsOf: output))
            #expect(report.hotspots.count == 1)
            #expect(report.hotspotCount == 1)
        }
    }

    @Test("A directory outside a git checkout says churn needs history, rather than reporting nothing")
    func nonRepositoryDirectoryIsAnError() async throws {
        try await CLITestSupport.withTempDirectory { directory in
            try CLITestSupport.writeSampleSwiftSource(in: directory)
            var command = try CLITestSupport.parseHotspots(
                ["--source", directory.path, "--language", "swift"])

            do {
                try await command.run()
                Issue.record("Expected a failure naming the missing history.")
            } catch {
                let message = CLITestSupport.message(for: error)
                #expect(message.contains("not inside a git checkout"))
                #expect(message.contains("commit history"))
            }
        }
    }

    @Test("A missing source directory is rejected before any history walk")
    func missingSourceDirectoryIsRejected() async throws {
        var command = try CLITestSupport.parseHotspots(["--source", CLITestSupport.nonexistentPath()])
        await #expect(throws: (any Error).self) { try await command.run() }
    }

    @Test("--commits must be at least 1")
    func commitsMustBePositive() throws {
        #expect(throws: (any Error).self) {
            try CLITestSupport.parseHotspots(["--source", "/tmp", "--commits", "0"])
        }
    }

    @Test("--top must be at least 1")
    func topMustBePositive() throws {
        #expect(throws: (any Error).self) {
            try CLITestSupport.parseHotspots(["--source", "/tmp", "--top", "0"])
        }
    }

    private struct Report: Decodable {
        struct File: Decodable {
            let path: String
            let churn: Int
            let complexity: Int
            let score: Int
        }
        let hotspots: [File]
        let commitWindow: Int
        let filesScored: Int
        let hotspotCount: Int
    }
}
#endif
