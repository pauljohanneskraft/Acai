import ArgumentParser
import AcaiDiagram

enum FormatOption: String, ExpressibleByArgument, CaseIterable {
    case dot
    case mermaid

    var diagramFormat: DiagramFormat {
        switch self {
        case .dot:
            return .dot
        case .mermaid:
            return .mermaid
        }
    }
}
