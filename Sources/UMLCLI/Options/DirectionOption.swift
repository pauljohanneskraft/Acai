import ArgumentParser
import UMLDiagram

enum DirectionOption: String, ExpressibleByArgument, CaseIterable {
    case TB, LR, BT, RL

    var layoutDirection: DiagramOptions.LayoutDirection {
        switch self {
        case .TB: return .topToBottom
        case .LR: return .leftToRight
        case .BT: return .bottomToTop
        case .RL: return .rightToLeft
        }
    }
}
