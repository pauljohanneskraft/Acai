/// A small, fixed set of pre-arranged starting points for a new freeform diagram (B26) — existing
/// catalog node kinds pre-positioned for a conventional starting shape, offered alongside a blank
/// diagram in the "New Freeform Diagram" flow. Deliberately modest: not a template-authoring
/// system, just removing the blank-page problem for the diagram kinds the catalog already models
/// structurally.
enum FreeformDiagramTemplate: String, CaseIterable, Identifiable {
    case useCase
    case deployment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useCase:
            "Use Case"
        case .deployment:
            "Deployment"
        }
    }

    var systemImage: String {
        switch self {
        case .useCase:
            "person.crop.rectangle"
        case .deployment:
            "cube"
        }
    }

    /// The pre-arranged starting nodes for this template, positioned and ready to connect.
    var nodes: [FreeformDiagram.Node] {
        switch self {
        case .useCase:
            [
                FreeformDiagram.Node(name: "Actor", content: .actor, positionX: 160, positionY: 220),
                FreeformDiagram.Node(
                    name: "System", content: .boundary,
                    positionX: 480, positionY: 220, width: 260, height: 180
                )
            ]
        case .deployment:
            [
                FreeformDiagram.Node(name: "Client", content: .deploymentNode, positionX: 160, positionY: 220),
                FreeformDiagram.Node(name: "Server", content: .deploymentNode, positionX: 460, positionY: 220)
            ]
        }
    }
}
