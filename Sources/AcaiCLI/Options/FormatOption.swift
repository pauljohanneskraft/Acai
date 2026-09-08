import ArgumentParser
import AcaiDiagram

enum FormatOption: String, ExpressibleByArgument, CaseIterable {
    case dot
    case mermaid
    case svg

    /// `nil` for `.svg`: it isn't a `DiagramExport` format, it renders the `.dot` text through Graphviz.
    var diagramFormat: DiagramFormat? {
        switch self {
        case .dot:
            return .dot
        case .mermaid:
            return .mermaid
        case .svg:
            return nil
        }
    }
}
