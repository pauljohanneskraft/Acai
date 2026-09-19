import Foundation
import Testing
@testable import AcaiApp

@Suite("Browser windows")
@MainActor
struct BrowserWindowsTests {
    private func withTempStoreDir<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-browser-windows-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    @Test func aDiagramShownInOneWindowIsOpenElsewhereForAnother() {
        let windows = BrowserWindows()
        let first = UUID(), second = UUID(), diagram = UUID()

        #expect(windows.claim(diagram, for: first))
        #expect(!windows.claim(diagram, for: second))
        #expect(windows.isOpenElsewhere(diagram, from: second))
        #expect(!windows.isOpenElsewhere(diagram, from: first))
        #expect(windows.owner(of: diagram) == first)
    }

    @Test func movingOnOrClosingReleasesTheDiagram() {
        let windows = BrowserWindows()
        let first = UUID(), second = UUID(), diagram = UUID()
        windows.claim(diagram, for: first)

        windows.claim(UUID(), for: first)
        #expect(windows.claim(diagram, for: second))

        windows.windowClosed(second)
        #expect(windows.owner(of: diagram) == nil)
    }

    @Test func focusingTheOwnerRunsItsFocusAction() {
        let windows = BrowserWindows()
        let owner = UUID(), diagram = UUID()
        var focused = false
        windows.windowOpened(owner) { focused = true }
        windows.claim(diagram, for: owner)

        #expect(windows.focusOwner(of: diagram))
        #expect(focused)
        #expect(!windows.focusOwner(of: UUID()))
    }

    @Test func theLastActiveWindowPresentsSharedState() {
        let windows = BrowserWindows()
        let first = UUID(), second = UUID()
        windows.windowOpened(first) {}
        windows.windowOpened(second) {}
        #expect(windows.lastActiveWindow == first)

        windows.windowBecameActive(second)
        #expect(windows.lastActiveWindow == second)

        windows.windowClosed(second)
        #expect(windows.lastActiveWindow == first)
    }

    @Test func aDeleteInOneWindowClearsAnotherWindowsSelection() async throws {
        try await withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let first = ProjectBrowserViewModel(store: store)
            let second = ProjectBrowserViewModel(store: store)
            let projectID = first.editing.addProject(title: "Demo", subtitle: "")
            let diagramID = try #require(first.freeforms.add(to: projectID, name: "Sketch"))
            second.selection = .freeformDiagram(diagramID)

            first.freeforms.remove(diagramID)
            await Task.yield()

            #expect(second.selection == nil)
        }
    }

    @Test func anAnalysisInvalidationReachesEveryWindow() async throws {
        try await withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let first = ProjectBrowserViewModel(store: store)
            let second = ProjectBrowserViewModel(store: store)
            let codebaseID = UUID()
            let before = second.analysisToken(for: codebaseID)

            first.invalidateAnalysis(codebaseID: codebaseID)

            #expect(second.analysisToken(for: codebaseID) != before)
        }
    }

    @Test func movingADiagramToItsOwnWindowLeavesThisWindowOnItsParent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-browser-windows-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)
        let model = ProjectBrowserViewModel(store: store)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        let codebaseID = UUID()
        let generatedID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        let freeformID = try #require(model.freeforms.add(to: projectID, name: "Sketch"))

        #expect(model.parentSelection(ofDiagram: generatedID) == .codebase(codebaseID))
        #expect(model.parentSelection(ofDiagram: freeformID) == .project(projectID))
    }
}
