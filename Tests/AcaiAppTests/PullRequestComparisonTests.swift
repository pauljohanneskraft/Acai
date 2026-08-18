import Foundation
import Testing
@testable import AcaiApp

/// End-to-end coverage of the pull-request comparison path: `selectComparisonPullRequest` +
/// `ensureComparisonLoaded` resolving `GitCheckout.mergeBase` and loading both sides as historical
/// snapshots — proving three-dot semantics (the base branch's own unrelated later commits don't
/// leak into the diff) through the real view model, not just `GitCheckout` in isolation.
@Suite("ProjectBrowserViewModel pull-request comparison")
@MainActor
struct PullRequestComparisonTests {
    private func makeTempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-pr-comparison-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
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

    /// `main` forks a `pr-head` branch after committing `Foo`, then `main` advances on its own with
    /// an unrelated `Bar` type — the base moving on after the PR forked, which three-dot semantics
    /// must not leak into the comparison. `pr-head` separately adds `Widget`.
    private func makePullRequestFixture(in dir: URL) throws {
        try git(["init", "-q", "--initial-branch=main"], in: dir)
        try "class Foo {}\n".write(to: dir.appendingPathComponent("Foo.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "initial"], in: dir)

        try git(["checkout", "-q", "-b", "pr-head"], in: dir)
        try "class Widget {}\n".write(to: dir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "add widget"], in: dir)

        try git(["checkout", "-q", "main"], in: dir)
        try "class Bar {}\n".write(to: dir.appendingPathComponent("Bar.swift"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: dir)
        try git(["commit", "-q", "-m", "unrelated main-only change"], in: dir)
    }

    @Test func loadsMergeBaseAsOldSideAndHeadAsNewSideExcludingBasesLaterCommits() async throws {
        let repoDir = try makeTempDirectory("repo")
        let storeDir = try makeTempDirectory("store")
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: storeDir)
        }
        try makePullRequestFixture(in: repoDir)

        let store = ProjectStore(baseDir: storeDir)
        let model = ProjectBrowserViewModel(store: store)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        model.editing.addCodebase(to: projectID, name: "Demo", directoryURL: repoDir)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))

        model.selectComparisonPullRequest(diagramID: diagramID, base: "main", head: "pr-head")
        let diagram = try #require(model.generatedDiagram(for: diagramID))
        #expect(diagram.comparisonGitRef == "pr-head")
        #expect(diagram.comparisonBaseRef == "main")

        await model.ensureComparisonLoaded(for: diagram)

        let oldNames = Set((model.comparisonArtifact(for: diagram)?.types ?? []).map(\.name))
        let newNames = Set((model.comparisonNewArtifact(for: diagram)?.types ?? []).map(\.name))

        // Old side is the merge-base (right after "initial"): only Foo, not main's later Bar.
        #expect(oldNames == ["Foo"])
        // New side is the PR head: Foo (inherited) + Widget, but never Bar (main-only).
        #expect(newNames == ["Foo", "Widget"])
        #expect(model.comparisonError == nil)
    }

    @Test func updatingComparisonGitRefExitsPullRequestModeAndResetsReviewState() async throws {
        let repoDir = try makeTempDirectory("repo")
        let storeDir = try makeTempDirectory("store")
        defer {
            try? FileManager.default.removeItem(at: repoDir)
            try? FileManager.default.removeItem(at: storeDir)
        }
        try makePullRequestFixture(in: repoDir)

        let store = ProjectStore(baseDir: storeDir)
        let model = ProjectBrowserViewModel(store: store)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        model.editing.addCodebase(to: projectID, name: "Demo", directoryURL: repoDir)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))

        model.selectComparisonPullRequest(diagramID: diagramID, base: "main", head: "pr-head")
        model.toggleComparisonFileReviewed(diagramID: diagramID, filePath: "Widget.swift")
        #expect(model.isComparisonFileReviewed(diagramID: diagramID, filePath: "Widget.swift"))

        model.updateComparisonGitRef(diagramID: diagramID, ref: "HEAD")

        let diagram = try #require(model.generatedDiagram(for: diagramID))
        #expect(diagram.comparisonGitRef == "HEAD")
        #expect(diagram.comparisonBaseRef == nil)
        #expect(!model.isComparisonFileReviewed(diagramID: diagramID, filePath: "Widget.swift"))
    }
}
