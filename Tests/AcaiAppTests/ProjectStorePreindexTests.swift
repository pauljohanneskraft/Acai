import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("Project Store fixture preindexing", .timeLimit(.minutes(1)))
@MainActor
struct ProjectStorePreindexTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-preindex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func marksTheCodebaseIndexedAndLoadsTheArtifact() async throws {
        let storeDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let sourceDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        try Data("struct Demo {}".utf8).write(to: sourceDir.appendingPathComponent("Demo.swift"))

        let analysisStore = AnalysisStore(directory: storeDir.appendingPathComponent("analysis"))
        let store = ProjectStore(baseDir: storeDir, analysisStore: analysisStore)
        let codebase = Codebase(name: "Demo", directoryPath: sourceDir.path)
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Demo.swift"]))

        await store.preindex(
            ProjectStore.FixturePreindex(
                codebaseID: codebase.id, projectID: project.id, sourcePath: sourceDir.path, artifact: artifact
            )
        )

        #expect(store.projects.first?.codebases.first?.hasArtifact == true)
        #expect(store.projects.first?.codebases.first?.lastIndexed == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(store.projects.first?.codebases.first?.indexedFingerprint != nil)
        #expect(store.artifacts[codebase.id] == artifact)

        if case .entry(let entry) = analysisStore.lookup(forResolvedPath: sourceDir.path) {
            #expect(entry.artifact == artifact)
        } else {
            Issue.record("expected an analysis entry for the preindexed codebase")
        }
    }

    @Test func leavesTheCodebaseUnindexedWhenTheAnalysisStoreCannotBeWrittenTo() async throws {
        let storeDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let sourceDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        // A plain file where the analysis store wants its directory, so its write throws.
        let unwritableAnalysisDir = storeDir.appendingPathComponent("analysis")
        try Data().write(to: unwritableAnalysisDir)
        let analysisStore = AnalysisStore(directory: unwritableAnalysisDir)
        let store = ProjectStore(baseDir: storeDir, analysisStore: analysisStore)
        let codebase = Codebase(name: "Demo", directoryPath: sourceDir.path)
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []))

        await store.preindex(
            ProjectStore.FixturePreindex(
                codebaseID: codebase.id, projectID: project.id, sourcePath: sourceDir.path, artifact: artifact
            )
        )

        #expect(store.projects.first?.codebases.first?.hasArtifact == false)
        #expect(store.artifacts[codebase.id] == nil)
    }

    @Test func aReindexSavedWhilePreindexingIsInFlightLandsLast() async throws {
        let storeDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let sourceDir = try makeTempDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        try Data("struct Demo {}".utf8).write(to: sourceDir.appendingPathComponent("Demo.swift"))

        let analysisStore = AnalysisStore(directory: storeDir.appendingPathComponent("analysis"))
        let store = ProjectStore(baseDir: storeDir, analysisStore: analysisStore)
        let codebase = Codebase(name: "Demo", directoryPath: sourceDir.path)
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]
        let canned = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Canned.swift"]))
        let reindexed = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Demo.swift"]))

        store.startFixturePreindexing([
            ProjectStore.FixturePreindex(
                codebaseID: codebase.id, projectID: project.id, sourcePath: sourceDir.path, artifact: canned
            )
        ])
        try await store.saveArtifactAndWait(reindexed, for: codebase.id)

        #expect(store.artifacts[codebase.id] == reindexed)
        if case .entry(let entry) = analysisStore.lookup(forResolvedPath: sourceDir.path) {
            #expect(entry.artifact == reindexed)
        } else {
            Issue.record("expected an analysis entry for the reindexed codebase")
        }
    }
}
