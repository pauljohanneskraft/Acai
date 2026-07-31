enum DiagramType: String, Codable, CaseIterable, Identifiable, Sendable {
    case classDiagram = "class"
    case sequenceDiagram = "sequence"
    case stateDiagram = "state"
    case packageDiagram = "package"
    case callGraph = "callGraph"
    /// Every module plotted on an Abstractness-vs-Instability "main sequence" chart — a new view
    /// over `CodeMetrics.ModuleCoupling`, already computed but today only shown one number at a
    /// time in `CodebaseDetailView`'s stat cards.
    case moduleCoupling = "moduleCoupling"
    /// Churn (commits touching a file) × complexity (`CodeMetrics.TypeMetric.maxCyclomaticComplexity`)
    /// scatter — the classic hotspot technique; its top-right quadrant is the hotspot list.
    case hotspot = "hotspot"
    /// Isolates and renders exactly one detected `AcaiQuality.CycleFinder` cycle's members/edges,
    /// laid out as the loop it is. Not offered from the general "add a diagram" grid — see
    /// `CodebaseDetailView.diagramsBar` — since a cycle diagram has no meaningful content until a
    /// specific cycle is chosen; reached instead via "View as Diagram" on a Quality Check cycle
    /// violation row.
    case cycleDiagram = "cycleDiagram"

    var id: String { rawValue }

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
        case .cycleDiagram:
            "Cycle Diagram"
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
        case .cycleDiagram:
            "arrow.triangle.2.circlepath"
        }
    }
}
