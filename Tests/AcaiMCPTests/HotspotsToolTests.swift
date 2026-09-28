// `acai_hotspots` walks git history via `AcaiGit`, so it exists on macOS only; the fixture shells
// out to real `git`.
#if os(macOS)
import Foundation
import MCP
import Testing
@testable import AcaiMCP

@Suite("Hotspots Tool")
struct HotspotsToolTests {

    /// `Hot.swift` is touched by three commits and branches; `Cold.swift` is touched once and does
    /// not. The parentless root commit contributes no touches, so `Seed.md` carries it.
    private func buildRepository(in directory: URL) throws {
        try git(["init", "-q", "--initial-branch=main"], in: directory)
        try write("Seed.md", "seed\n", in: directory)
        try commit("seed", in: directory)

        try write("Cold.swift", "class Cold {\n    func value() -> Int { 1 }\n}\n", in: directory)
        try write("Hot.swift", hotSource(returning: 0), in: directory)
        try commit("add sources", in: directory)

        try write("Hot.swift", hotSource(returning: 1), in: directory)
        try commit("edit hot", in: directory)

        try write("Hot.swift", hotSource(returning: 2), in: directory)
        try commit("edit hot again", in: directory)
    }

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

    private func write(_ name: String, _ contents: String, in directory: URL) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func commit(_ message: String, in directory: URL) throws {
        try git(["add", "-A"], in: directory)
        try git(["commit", "-q", "-m", message], in: directory)
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
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

    @Test func rankedListMatchesTheCLIReportsStructure() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try buildRepository(in: dir)
            let value = try await MCPTestSupport.call("acai_hotspots", on: MCPTestSupport.testRegistry, path: dir)
            let object = try #require(value.objectValue)

            #expect(object["commitWindow"]?.intValue == 50)
            #expect(object["filesScored"]?.intValue == 2)
            #expect(object["churnThreshold"] != nil)
            #expect(object["complexityThreshold"] != nil)

            let hotspots = try #require(object["hotspots"]?.arrayValue)
            let first = try #require(hotspots.first?.objectValue)
            #expect(first["path"]?.stringValue == "Hot.swift")
            #expect(first["type"]?.stringValue == "Hot")
            #expect(first["churn"]?.intValue == 3)
            #expect(first["score"] != nil)
            #expect(first["isHotspot"]?.boolValue == true)
        }
    }

    @Test func aDirectoryOutsideAGitCheckoutIsRejected() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try MCPTestSupport.writeSampleSwiftSource(in: dir)
            await #expect(throws: MCPError.self) {
                try await MCPTestSupport.call("acai_hotspots", on: MCPTestSupport.testRegistry, path: dir)
            }
        }
    }

    @Test func aNonPositiveCommitWindowIsRejected() async throws {
        try await MCPTestSupport.withTempDirectory { dir in
            try buildRepository(in: dir)
            await #expect(throws: MCPError.self) {
                try await MCPTestSupport.call(
                    "acai_hotspots", on: MCPTestSupport.testRegistry, path: dir, ["commits": .int(0)])
            }
        }
    }
}
#endif
