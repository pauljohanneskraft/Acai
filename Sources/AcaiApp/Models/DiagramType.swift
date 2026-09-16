import Foundation

enum DiagramType: String, Codable, CaseIterable, Identifiable, Sendable {
    case classDiagram = "class"
    case sequenceDiagram = "sequence"
    case stateDiagram = "state"
    case packageDiagram = "package"
    case callGraph = "callGraph"
    case moduleCoupling = "moduleCoupling"
    case hotspot = "hotspot"

    var id: String { rawValue }

    /// The interface's name for the kind. `displayName` stays English: it seeds persisted diagram
    /// names and exported atlas text, which must not change with the reader's language.
    var title: LocalizedStringResource {
        switch self {
        case .classDiagram:
            .app("DiagramType.ClassDiagram")
        case .sequenceDiagram:
            .app("DiagramType.SequenceDiagram")
        case .stateDiagram:
            .app("DiagramType.StateDiagram")
        case .packageDiagram:
            .app("DiagramType.PackageDiagram")
        case .callGraph:
            .app("DiagramType.CallGraph")
        case .moduleCoupling:
            .app("DiagramType.ModuleCoupling")
        case .hotspot:
            .app("DiagramType.Hotspots")
        }
    }

    var displayName: String {
        switch self {
        case .classDiagram:
            "Class Diagram"
        case .sequenceDiagram:
            "Sequence Diagram"
        case .stateDiagram:
            "State Diagram"
        case .packageDiagram:
            "Package Diagram"
        case .callGraph:
            "Call Graph"
        case .moduleCoupling:
            "Module Coupling"
        case .hotspot:
            "Hotspots"
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
        case .packageDiagram:
            "shippingbox"
        case .callGraph:
            "point.3.connected.trianglepath.dotted"
        case .moduleCoupling:
            "chart.xyaxis.line"
        case .hotspot:
            "flame"
        }
    }
}
