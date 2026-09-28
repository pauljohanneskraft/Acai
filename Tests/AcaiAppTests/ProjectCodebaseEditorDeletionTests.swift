import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Deleting is destructive and irreversible, and it reaches further than the row the user tapped: the
/// codebase's diagrams, its stored analysis and its managed rules all go with it, and a sibling's must
/// not. Until now nothing but a journey covered any of that.
@Suite("Codebase and project deletion", .timeLimit(.minutes(1)))
@MainActor
struct ProjectCodebaseEditorDeletionTests {
    @Test func deletingACodebaseTakesItsDiagramsAndAnalysisButLeavesASiblingsAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        await fixture.model.editing.removeCodebase(fixture.codebaseID)

        #expect(fixture.model.codebase(for: fixture.codebaseID) == nil)
        #expect(fixture.store.generatedDiagrams[fixture.diagramID] == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.generatedDiagramURL(fixture.diagramID).path))
        #expect(fixture.store.artifacts[fixture.codebaseID] == nil)

        #expect(fixture.model.codebase(for: fixture.siblingID) != nil)
        #expect(fixture.store.generatedDiagrams[fixture.siblingDiagramID] != nil)
        #expect(fixture.store.artifacts[fixture.siblingID] != nil)
    }

    @Test func deletingAProjectTakesEveryCodebasesData() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.model.editing.removeProject(fixture.projectID)

        #expect(fixture.store.projects.isEmpty)
        for diagramID in [fixture.diagramID, fixture.siblingDiagramID] {
            #expect(fixture.store.generatedDiagrams[diagramID] == nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.store.generatedDiagramURL(diagramID).path))
        }
    }

    @Test func deletingTheSelectedCodebaseClearsTheSelectionAndKeepsAnUnrelatedOne() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.model.selection = .codebase(fixture.codebaseID)
        await fixture.model.editing.removeCodebase(fixture.codebaseID)
        #expect(fixture.model.selection == nil)

        fixture.model.selection = .codebase(fixture.siblingID)
        #expect(fixture.model.selection == .codebase(fixture.siblingID))
    }

    /// One project holding two indexed codebases, each with a generated diagram, so a deletion has
    /// something to reach past.
    @MainActor
    private struct Fixture {
        let baseDir: URL
        let store: ProjectStore
        let model: ProjectBrowserViewModel
        let projectID: UUID
        let codebaseID = UUID()
        let siblingID = UUID()
        let diagramID: UUID
        let siblingDiagramID: UUID

        init() throws {
            baseDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("acai-deletion-tests-\(UUID().uuidString)", isDirectory: true)
            store = ProjectStore(
                baseDir: baseDir,
                analysisStore: AnalysisStore(directory: baseDir.appendingPathComponent("analysis-store")))
            var project = Project(
                title: "P", subtitle: "",
                codebases: [
                    Codebase(id: codebaseID, name: "C", directoryPath: baseDir.appendingPathComponent("c").path),
                    Codebase(id: siblingID, name: "S", directoryPath: baseDir.appendingPathComponent("s").path)
                ])
            let diagram = GeneratedDiagram(name: "C classes", content: .init(type: .classDiagram),
                                           codebaseID: codebaseID)
            let siblingDiagram = GeneratedDiagram(name: "S classes", content: .init(type: .classDiagram),
                                                  codebaseID: siblingID)
            diagramID = diagram.id
            siblingDiagramID = siblingDiagram.id
            project.generatedDiagramIDs = [diagram.id, siblingDiagram.id]
            projectID = project.id

            store.projects = [project]
            store.saveProject(project)
            store.saveGeneratedDiagram(diagram)
            store.saveGeneratedDiagram(siblingDiagram)
            for id in [codebaseID, siblingID] {
                store.artifacts[id] = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]))
            }
            model = ProjectBrowserViewModel(store: store)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: baseDir)
        }
    }
}
