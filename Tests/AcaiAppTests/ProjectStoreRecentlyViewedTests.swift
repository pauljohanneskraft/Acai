import Foundation
import Testing
@testable import AcaiApp

/// `ProjectStore`'s persistence of `RecentlyViewed`, and that deleting the underlying
/// diagram/codebase/project clears any dangling reference to it — the actual integration point
/// B54's model plugs into, even though nothing opens diagrams through it yet.
@Suite("ProjectStore recently viewed")
@MainActor
struct ProjectStoreRecentlyViewedTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-store-recent-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("recordOpened and togglePin persist across store instances")
    func recentlyViewedRoundTripsAcrossInstances() {
        withTempStoreDir { dir in
            let codebaseID = UUID()
            let store = ProjectStore(baseDir: dir)
            store.recordOpened(.codebase(codebaseID))
            store.togglePin(.codebase(codebaseID))

            let reloaded = ProjectStore(baseDir: dir)
            #expect(reloaded.recentlyViewed.recents == [.codebase(codebaseID)])
            #expect(reloaded.recentlyViewed.isPinned(.codebase(codebaseID)))
        }
    }

    @Test("Removing a generated diagram clears it from recently viewed")
    func removingGeneratedDiagramClearsRecentlyViewed() {
        withTempStoreDir { dir in
            let codebaseID = UUID()
            var project = Project(title: "Demo", subtitle: "")
            let diagram = GeneratedDiagram(name: "Classes", content: .init(type: .classDiagram), codebaseID: codebaseID)
            project.generatedDiagramIDs = [diagram.id]

            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)
            store.saveGeneratedDiagram(diagram)
            store.recordOpened(.generatedDiagram(diagram.id))

            let model = ProjectBrowserViewModel(store: store)
            model.diagrams.remove(diagram.id)

            #expect(!store.recentlyViewed.recents.contains(.generatedDiagram(diagram.id)))
        }
    }

    @Test("Removing a codebase clears it and its diagrams from recently viewed")
    func removingCodebaseClearsRecentlyViewed() {
        withTempStoreDir { dir in
            let codebase = Codebase(name: "Demo", directoryPath: "/tmp/demo")
            let diagram = GeneratedDiagram(
                name: "Classes", content: .init(type: .classDiagram), codebaseID: codebase.id
            )
            var project = Project(title: "Demo", subtitle: "")
            project.codebases = [codebase]
            project.generatedDiagramIDs = [diagram.id]

            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)
            store.saveGeneratedDiagram(diagram)
            store.recordOpened(.codebase(codebase.id))
            store.recordOpened(.generatedDiagram(diagram.id))

            let model = ProjectBrowserViewModel(store: store)
            model.editing.removeCodebase(codebase.id)

            #expect(!store.recentlyViewed.recents.contains(.codebase(codebase.id)))
            #expect(!store.recentlyViewed.recents.contains(.generatedDiagram(diagram.id)))
        }
    }

    @Test("Removing a project clears its codebases and diagrams from recently viewed")
    func removingProjectClearsRecentlyViewed() {
        withTempStoreDir { dir in
            let codebase = Codebase(name: "Demo", directoryPath: "/tmp/demo")
            let generated = GeneratedDiagram(
                name: "Classes", content: .init(type: .classDiagram), codebaseID: codebase.id
            )
            let freeform = FreeformDiagram(name: "Sketch")
            var project = Project(title: "Demo", subtitle: "")
            project.codebases = [codebase]
            project.generatedDiagramIDs = [generated.id]
            project.freeformDiagramIDs = [freeform.id]

            let store = ProjectStore(baseDir: dir)
            store.projects.append(project)
            store.saveProject(project)
            store.saveGeneratedDiagram(generated)
            store.saveFreeformDiagram(freeform)
            store.recordOpened(.codebase(codebase.id))
            store.recordOpened(.generatedDiagram(generated.id))
            store.recordOpened(.freeformDiagram(freeform.id))

            let model = ProjectBrowserViewModel(store: store)
            model.editing.removeProject(project.id)

            #expect(store.recentlyViewed.recents.isEmpty)
        }
    }
}
