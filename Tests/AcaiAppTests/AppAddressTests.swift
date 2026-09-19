import Foundation
import Testing
@testable import AcaiApp

@Suite("App addresses")
@MainActor
struct AppAddressTests {
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-app-address-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test(arguments: [AppAddress.project(UUID()), .codebase(UUID()), .diagram(UUID())])
    func urlRoundTrips(_ address: AppAddress) {
        #expect(AppAddress(url: address.url) == address)
    }

    @Test func urlHasTheDocumentedShape() {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        #expect(AppAddress.codebase(id).url.absoluteString == "acai://codebase/22222222-2222-2222-2222-222222222222")
    }

    @Test func parsingIgnoresTheCaseOfSchemeKindAndID() throws {
        let url = try #require(URL(string: "ACAI://Diagram/33333333-3333-3333-3333-33333333333a"))
        #expect(AppAddress(url: url) == .diagram(UUID(uuidString: "33333333-3333-3333-3333-33333333333A")!))
    }

    @Test(arguments: [
        "https://codebase/22222222-2222-2222-2222-222222222222",
        "acai://codebase/not-a-uuid",
        "acai://codebase/22222222-2222-2222-2222-222222222222/extra",
        "acai://codebase",
        "acai://repository/22222222-2222-2222-2222-222222222222",
        "acai://codebase/22222222-2222-2222-2222-222222222222?x=1"
    ])
    func malformedURLsAreRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(AppAddress(url: url) == nil)
    }

    @Test func eachAddressResolvesToWhatItNames() throws {
        try withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            model.editing.addCodebase(to: projectID, name: "App", directoryURL: dir)
            let codebaseID = try #require(store.projects.first?.codebases.first?.id)
            let generatedID = try #require(
                model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
            let freeformID = try #require(model.freeforms.add(to: projectID, name: "Sketch"))

            #expect(try model.selection(for: .project(projectID)) == .project(projectID))
            #expect(try model.selection(for: .codebase(codebaseID)) == .codebase(codebaseID))
            #expect(try model.selection(for: .diagram(generatedID)) == .generatedDiagram(generatedID))
            #expect(try model.selection(for: .diagram(freeformID)) == .freeformDiagram(freeformID))
        }
    }

    @Test func anAddressToSomethingDeletedFailsWithoutMovingTheSelection() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            model.selection = .project(projectID)

            #expect(throws: ProjectBrowserViewModel.AddressFailure.diagramNotFound) {
                try model.selection(for: .diagram(UUID()))
            }
            #expect(throws: ProjectBrowserViewModel.AddressFailure.codebaseNotFound) {
                try model.selection(for: .codebase(UUID()))
            }
            #expect(model.resolve(url: AppAddress.project(UUID()).url) == nil)
            #expect(store.lastError != nil)
            #expect(model.selection == .project(projectID))
        }
    }

    @Test func aMalformedLinkIsReported() throws {
        try withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)

            let url = try #require(URL(string: "acai://nothing"))
            #expect(model.resolve(url: url) == nil)
            #expect(store.lastError?.message.contains("acai://nothing") == true)
        }
    }

    @Test func everySelectionTheAppOwnsHasAnAddress() {
        let id = UUID()
        #expect(ProjectBrowserViewModel.Selection.findings(id).address == .project(id))
        #expect(ProjectBrowserViewModel.Selection.query(id).address == .codebase(id))
        #expect(ProjectBrowserViewModel.Selection.freeformDiagram(id).address == .diagram(id))
        #expect(ProjectBrowserViewModel.Selection.repository(URL(string: "https://example.com/r.git")!).address == nil)
    }
}
