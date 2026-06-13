import ArgumentParser
import UMLCore

enum FocusDirectionOption: String, ExpressibleByArgument, CaseIterable {
    case dependencies
    case dependents
    case both

    var direction: FocusConfiguration.Direction {
        switch self {
        case .dependencies:
            return .dependencies
        case .dependents:
            return .dependents
        case .both:
            return .both
        }
    }
}
