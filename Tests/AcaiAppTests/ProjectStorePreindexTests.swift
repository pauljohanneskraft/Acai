import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// `preindex(_:)` awaited directly, rather than through the task `load()` retains for it.
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

        // A plain file where `write(_:sourcePath:fingerprint:)` wants to create its directory: its own
        // `createDirectory(at:)` throws, so the write — and with it, marking the codebase indexed — fails.
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

    @Test func leavesACodebaseIndexedWhileItWasInFlightUntouched() async throws {
        let storeDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let sourceDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: sourceDir) }
        try Data("struct Demo {}".utf8).write(to: sourceDir.appendingPathComponent("Demo.swift"))

        let analysisStore = AnalysisStore(directory: storeDir.appendingPathComponent("analysis"))
        let store = ProjectStore(baseDir: storeDir, analysisStore: analysisStore)
        var codebase = Codebase(name: "Demo", directoryPath: sourceDir.path)
        codebase.hasArtifact = true
        var project = Project(title: "Demo", subtitle: "")
        project.codebases = [codebase]
        store.projects = [project]
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Demo.swift"]))

        await store.preindex(
            ProjectStore.FixturePreindex(
                codebaseID: codebase.id, projectID: project.id, sourcePath: sourceDir.path, artifact: artifact
            )
        )

        #expect(store.projects.first?.codebases.first?.lastIndexed == nil)
        #expect(store.projects.first?.codebases.first?.indexedFingerprint == nil)
    }
}
