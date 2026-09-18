import Foundation
import Testing
@testable import AcaiApp

@Suite("Dropping folders onto a project")
@MainActor
struct FolderDropTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("acai-folder-drop-tests-\(UUID().uuidString)", isDirectory: true)

    private func makeModel() throws -> (model: ProjectBrowserViewModel, projectID: UUID) {
        let storeDir = root.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let model = ProjectBrowserViewModel(store: ProjectStore(baseDir: storeDir))
        return (model, model.editing.addProject(title: "Demo", subtitle: ""))
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func codebases(in model: ProjectBrowserViewModel, _ projectID: UUID) -> [Codebase] {
        model.store.projects.first { $0.id == projectID }?.codebases ?? []
    }

    @Test func addsEveryDroppedFolderNamedAfterIt() throws {
        let (model, projectID) = try makeModel()
        let folders = try [makeFolder("App"), makeFolder("Server")].map { DroppedFolder(url: $0) }

        let outcome = model.editing.addCodebases(from: folders, to: projectID)

        #expect(outcome == FolderDropOutcome(added: 2, alreadyPresent: 0))
        #expect(codebases(in: model, projectID).map(\.name) == ["App", "Server"])
    }

    @Test func skipsAFolderTheProjectAlreadyHas() throws {
        let (model, projectID) = try makeModel()
        let app = try makeFolder("App")
        model.editing.addCodebase(to: projectID, name: "Renamed", directoryURL: app)

        let outcome = model.editing.addCodebases(
            from: [DroppedFolder(url: app), DroppedFolder(url: try makeFolder("Server"))], to: projectID)

        #expect(outcome == FolderDropOutcome(added: 1, alreadyPresent: 1))
        #expect(codebases(in: model, projectID).map(\.name) == ["Renamed", "Server"])
    }

    @Test func theSameFolderDroppedTwiceIsAddedOnce() throws {
        let (model, projectID) = try makeModel()
        let app = try makeFolder("App")

        let outcome = model.editing.addCodebases(
            from: [DroppedFolder(url: app), DroppedFolder(url: app)], to: projectID)

        #expect(outcome == FolderDropOutcome(added: 1, alreadyPresent: 1))
    }

    @Test func anUnknownProjectAddsNothing() throws {
        let (model, _) = try makeModel()
        let outcome = model.editing.addCodebases(from: [DroppedFolder(url: try makeFolder("App"))], to: UUID())
        #expect(outcome == FolderDropOutcome())
    }

    @Test func theLoaderKeepsFoldersAndIgnoresFiles() async throws {
        let folder = try makeFolder("App")
        let file = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)

        let loaded = await FolderDropLoader().folders(
            from: [NSItemProvider(object: folder as NSURL), NSItemProvider(object: file as NSURL)])

        #expect(loaded.folders.map(\.url.lastPathComponent) == ["App"])
        #expect(loaded.bookmarkFailures.isEmpty)
        #expect(loaded.folders.first?.securityScopedBookmark != nil)
    }
}
