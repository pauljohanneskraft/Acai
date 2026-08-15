import Foundation
import Testing
import AcaiCore
import AcaiRender
import AcaiQuality
@testable import AcaiApp

/// Covers the config-mutation binding the Filter section's `SelectorEditor` writes through
/// (`ClassDiagramConfigEditor.mutate`) — a unit test rather than a render snapshot, since the
/// section itself is `Form`-based (see the module's render-snapshot exclusions).
@Suite("Class Diagram Filter Config Editor")
@MainActor
struct ClassDiagramFilterConfigEditorTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-class-diagram-filter-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    private func type(_ name: String) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "A.swift", line: 1, column: 1)
        )
    }

    @Test("Setting the filter through the config editor persists it and applies it to the live diagram")
    func mutatingFilterPersistsAndApplies() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            model.editing.addCodebase(to: projectID, name: "Code", directoryURL: URL(fileURLWithPath: "/tmp/code"))
            let codebaseID = store.projects[0].codebases[0].id

            let artifact = CodeArtifact(
                metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
                types: [type("Repository"), type("View")]
            )
            guard let diagramID = model.diagrams.add(
                to: projectID, codebaseID: codebaseID, content: .classDiagram(.init())
            ) else {
                Issue.record("expected a diagram id")
                return
            }
            let diagram = store.generatedDiagrams[diagramID]!
            let viewModel = ClassDiagramViewModel(
                codebase: store.projects[0].codebases[0], artifact: artifact, configuration: diagram.classConfiguration!
            )
            let editor = ClassDiagramConfigEditor(
                model: model, viewModel: viewModel, diagramID: diagramID, artifact: artifact)

            let filter = AcaiQuality.Selector(typeGlob: "Repository")
            editor.mutate { $0.filter = filter }

            #expect(store.generatedDiagrams[diagramID]?.classConfiguration?.filter == filter)
            #expect(viewModel.configuration.filter == filter)
            #expect(viewModel.nodes.map(\.id) == ["Repository"])
        }
    }
}
