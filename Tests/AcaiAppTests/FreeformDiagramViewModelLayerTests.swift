import Testing
import AcaiDiagram
@testable import AcaiApp

@Suite("FreeformDiagramViewModel canvas layers")
@MainActor
struct FreeformDiagramViewModelLayerTests {

    private func node(
        _ name: String, content: FreeformDiagram.Node.Content, drawOrder: Int
    ) -> FreeformDiagram.Node {
        FreeformDiagram.Node(name: name, content: content, drawOrder: drawOrder)
    }

    @Test func containerLayerKeepsOnlyResizableNodesInDrawOrder() {
        let viewModel = FreeformDiagramViewModel()
        viewModel.nodes = [
            node("Second", content: .package, drawOrder: 2),
            node("Actor", content: .actor, drawOrder: 0),
            node("First", content: .boundary, drawOrder: 1)
        ]
        #expect(viewModel.containerLayerNodes.map(\.name) == ["First", "Second"])
    }

    @Test func regularLayerExcludesContainersLifelinesAndFragmentsInDrawOrder() {
        let viewModel = FreeformDiagramViewModel()
        viewModel.nodes = [
            node("Package", content: .package, drawOrder: 0),
            node("Lifeline", content: .lifeline(.actor), drawOrder: 1),
            node("Fragment", content: .fragment(.init()), drawOrder: 2),
            node("Late", content: .actor, drawOrder: 4),
            node("Early", content: .useCase, drawOrder: 3)
        ]
        #expect(viewModel.regularLayerNodes.map(\.name) == ["Early", "Late"])
    }
}
