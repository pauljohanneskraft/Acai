import Foundation
import Testing
import UMLCore
@testable import UMLApp

@Suite("Project Store")
@MainActor
struct ProjectStoreTests {

    /// Runs `body` with a fresh, isolated store directory that is cleaned up afterwards.
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("uml-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test func roundTripsProjectsAcrossInstances() {
        withTempStoreDir { dir in
            let project = Project(title: "Demo", subtitle: "A sample")
            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)

            // A fresh store over the same directory must load the saved project verbatim.
            let reloaded = ProjectStore(baseDir: dir)
            #expect(reloaded.projects.map(\.id) == [project.id])
            #expect(reloaded.projects.first?.title == "Demo")
            #expect(reloaded.lastError == nil)
        }
    }

    @Test func roundTripsGeneratedDiagram() {
        withTempStoreDir { dir in
            let codebaseID = UUID()
            var project = Project(title: "Demo", subtitle: "")
            let diagram = GeneratedDiagram(
                name: "Classes",
                content: .init(type: .classDiagram),
                codebaseID: codebaseID
            )
            project.generatedDiagramIDs.append(diagram.id)

            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)
            store.saveGeneratedDiagram(diagram)

            let reloaded = ProjectStore(baseDir: dir)
            #expect(reloaded.generatedDiagrams[diagram.id]?.name == "Classes")
            #expect(reloaded.generatedDiagrams[diagram.id]?.content.type == .classDiagram)
            #expect(reloaded.lastError == nil)
        }
    }

    @Test func corruptDiagramFileSurfacesAnErrorWithoutCrashing() throws {
        try withTempStoreDir { dir in
            let codebaseID = UUID()
            var project = Project(title: "Demo", subtitle: "")
            let diagram = GeneratedDiagram(
                name: "Classes", content: .init(type: .classDiagram), codebaseID: codebaseID
            )
            project.generatedDiagramIDs.append(diagram.id)
            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)
            store.saveGeneratedDiagram(diagram)

            // Corrupt the diagram file on disk.
            let diagramFile = dir.appendingPathComponent("diagrams")
                .appendingPathComponent("generated_\(diagram.id.uuidString).json")
            try Data("not json".utf8).write(to: diagramFile)

            let reloaded = ProjectStore(baseDir: dir)
            // The corrupt diagram is dropped, the project still loads, and the failure is reported.
            #expect(reloaded.projects.map(\.id) == [project.id])
            #expect(reloaded.generatedDiagrams[diagram.id] == nil)
            #expect(reloaded.lastError != nil)
        }
    }
}
