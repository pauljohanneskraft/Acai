import Foundation
import Testing
@testable import AcaiApp

/// `FreeformDiagramTemplate` (B26): the pre-arranged starter node sets offered in "New Freeform
/// Diagram," and `FreeformDiagramEditor.add(to:name:template:)`'s seeding of them. Layer 0, per
/// the model half of this item — deliberately modest data, so a straightforward unit test.
@Suite("FreeformDiagram Templates")
struct FreeformDiagramTemplateTests {

    @Test("The Use Case template seeds an actor and a system boundary")
    func useCaseTemplateSeedsActorAndBoundary() {
        let nodes = FreeformDiagramTemplate.useCase.nodes
        #expect(nodes.contains { $0.content == .actor })
        #expect(nodes.contains { $0.content == .boundary })
    }

    @Test("The Deployment template seeds a couple of placeholder deployment nodes")
    func deploymentTemplateSeedsPlaceholderNodes() {
        let nodes = FreeformDiagramTemplate.deployment.nodes
        #expect(nodes.count >= 2)
        #expect(nodes.allSatisfy { $0.content == .deploymentNode })
    }

    @Test("Every template's nodes are distinct, non-overlapping positions")
    func templateNodesDoNotOverlap() {
        for template in FreeformDiagramTemplate.allCases {
            let positions = template.nodes.map { CGPoint(x: $0.positionX, y: $0.positionY) }
            let uniquePositions = Set(positions.map { "\($0.x),\($0.y)" })
            #expect(uniquePositions.count == positions.count, "\(template) has overlapping node positions")
        }
    }
}

@Suite("FreeformDiagramEditor template seeding")
@MainActor
struct FreeformDiagramEditorTemplateTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-freeform-template-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("Adding a diagram with a template seeds its starter nodes")
    func addWithTemplateSeedsNodes() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let project = Project(title: "Demo", subtitle: "")
            store.projects.append(project)
            store.saveProject(project)

            let model = ProjectBrowserViewModel(store: store)
            let id = model.freeforms.add(to: project.id, name: "Use Case", template: .useCase)

            let diagram = id.flatMap { store.freeformDiagrams[$0] }
            #expect(diagram?.nodes.count == FreeformDiagramTemplate.useCase.nodes.count)
        }
    }

    @Test("Adding a diagram without a template starts blank")
    func addWithoutTemplateStartsBlank() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let project = Project(title: "Demo", subtitle: "")
            store.projects.append(project)
            store.saveProject(project)

            let model = ProjectBrowserViewModel(store: store)
            let id = model.freeforms.add(to: project.id, name: "Blank")

            #expect(id.flatMap { store.freeformDiagrams[$0] }?.nodes.isEmpty == true)
        }
    }
}
