import ArgumentParser
import AcaiDiagram

enum GroupByOption: String, ExpressibleByArgument, CaseIterable {
    case file
    case namespace
    case none

    var groupingStrategy: ClassDiagramOptions.GroupingStrategy {
        switch self {
        case .file:
            return .byFile
        case .namespace:
            return .byNamespace
        case .none:
            return .none
        }
    }
}
