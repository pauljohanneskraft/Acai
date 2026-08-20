import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

// Fixture helper shells out to real `git` via `Process`, unavailable on iOS.
#if os(macOS)
@Suite("HotspotViewModel")
@MainActor
struct HotspotViewModelTests {
    private func makeTempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-hotspot-vm-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com"
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func artifact() -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Foo.swift"]), types: [
            TypeDeclaration(
                id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public,
                location: .init(filePath: "Foo.swift", line: 1, column: 1))
        ])
    }

    @Test func plainNonGitFolderReportsNoGitHistory() async throws {
        let dir = try makeTempDirectory("plain")
        defer { try? FileManager.default.removeItem(at: dir) }
        let codebase = Codebase(name: "Demo", directoryPath: dir.path)
        let vm = HotspotViewModel(artifact: artifact())

        await vm.load(codebase: codebase, gitRepositoriesDir: try makeTempDirectory("hub"))

        #expect(!vm.hasGitHistory)
        #expect(vm.chartData == nil)
        #expect(vm.loadError == nil)
    }

    @Test func realGitFolderPopulatesChartData() async throws {
        let dir = try makeTempDirectory("repo")
        defer { try? FileManager.default.removeItem(at: dir) }
        try git(["init", "-q", "--initial-branch=main"], in: dir)
        try "class Foo {}\n".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)
        try "class Foo { let x = 1 }\n".write(
            to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "edit"], in: dir)

        let codebase = Codebase(name: "Demo", directoryPath: dir.path)
        let vm = HotspotViewModel(artifact: artifact())

        await vm.load(codebase: codebase, gitRepositoriesDir: try makeTempDirectory("hub"))

        #expect(vm.hasGitHistory)
        #expect(vm.loadError == nil)
        let data = try #require(vm.chartData)
        #expect(!data.points.isEmpty)
    }
}
#endif
