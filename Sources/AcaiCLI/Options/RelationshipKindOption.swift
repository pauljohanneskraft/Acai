import ArgumentParser
import AcaiCore

/// CLI spelling of `Relationship.Kind`, used by `--focus-relationship` to restrict which
/// relationship kinds the focus traversal follows and draws.
enum RelationshipKindOption: String, ExpressibleByArgument, CaseIterable {
    case inheritance
    case conformance
    case composition
    case aggregation
    case association
    case dependency
    case `extension`
    case nesting

    var kind: Relationship.Kind {
        switch self {
        case .inheritance:
            return .inheritance
        case .conformance:
            return .conformance
        case .composition:
            return .composition
        case .aggregation:
            return .aggregation
        case .association:
            return .association
        case .dependency:
            return .dependency
        case .extension:
            return .extension
        case .nesting:
            return .nesting
        }
    }
}
