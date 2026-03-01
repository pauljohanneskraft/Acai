enum DiagramType: String, Codable, CaseIterable, Identifiable, Sendable {
    case classDiagram = "class"
    case sequenceDiagram = "sequence"
    case stateDiagram = "state"
    case useCaseDiagram = "useCase"
    case deploymentDiagram = "deployment"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classDiagram:
            "Class Diagram"
        case .sequenceDiagram:
            "Sequence Diagram"
        case .stateDiagram:
            "State Diagram"
        case .useCaseDiagram:
            "Use Case Diagram"
        case .deploymentDiagram:
            "Deployment Diagram"
        }
    }

    var systemImage: String {
        switch self {
        case .classDiagram:
            "rectangle.3.group"
        case .sequenceDiagram:
            "arrow.right.arrow.left"
        case .stateDiagram:
            "circle.hexagonpath"
        case .useCaseDiagram:
            "person.3"
        case .deploymentDiagram:
            "server.rack"
        }
    }
}
