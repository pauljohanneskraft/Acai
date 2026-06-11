import UMLCore

/// Identifies the kind of element in a custom diagram.
///
/// Used for **catalog selection** (picking which element to add) and **display logic**
/// (icons, colours, labels). The actual per-node data lives in ``NodeContent``.
enum CustomDiagramNodeKind: Equatable, Hashable, Sendable, Identifiable {

    /// A code-analysis type (class, struct, enum, protocol, …).
    /// The associated `TypeKind` carries the specific kind.
    case type(TypeKind)

    // MARK: - UML Use-Case Diagram Elements

    case actor
    case useCase
    case boundary

    // MARK: - UML Component / Deployment Diagram Elements

    case component
    case package
    case deploymentNode
    case database
    case artifact
    case subsystem

    // MARK: - General UML Elements

    case entity
    case note

    // MARK: - Sequence Diagram Elements

    /// A sequence-diagram lifeline (participant). Created when a sequence diagram is saved as a
    /// custom diagram, and available in the catalog for building sequence diagrams by hand.
    case lifeline
    /// A sequence-diagram combined fragment (`loop`/`alt`/`opt`/…) framing a span of messages.
    case fragment

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .type(let tk):
            "type.\(tk.rawValue)"
        case .actor:
            "actor"
        case .useCase:
            "useCase"
        case .boundary:
            "boundary"
        case .component:
            "component"
        case .package:
            "package"
        case .deploymentNode:
            "deploymentNode"
        case .database:
            "database"
        case .artifact:
            "artifact"
        case .subsystem:
            "subsystem"
        case .entity:
            "entity"
        case .note:
            "note"
        case .lifeline:
            "lifeline"
        case .fragment:
            "fragment"
        }
    }

    // MARK: - Display Helpers

    /// A human-readable display name.
    var displayName: String {
        switch self {
        case .type(let tk):
            switch tk {
            case .class:
                "Class"
            case .actor:
                "Actor"
            case .struct:
                "Struct"
            case .enum:
                "Enum"
            case .protocol:
                "Protocol"
            case .interface:
                "Interface"
            case .trait:
                "Trait"
            case .typeAlias:
                "Type Alias"
            case .object:
                "Object"
            case .extension:
                "Extension"
            case .annotation:
                "Annotation"
            case .module:
                "Module"
            case .record:
                "Record"
            case .mixin:
                "Mixin"
            }
        case .actor:
            "Actor"
        case .useCase:
            "Use Case"
        case .boundary:
            "Boundary"
        case .component:
            "Component"
        case .package:
            "Package"
        case .deploymentNode:
            "Node"
        case .database:
            "Database"
        case .artifact:
            "Artifact"
        case .subsystem:
            "Subsystem"
        case .entity:
            "Entity"
        case .note:
            "Note"
        case .lifeline:
            "Lifeline"
        case .fragment:
            "Fragment (loop/alt/opt)"
        }
    }

    /// SF Symbol name for catalog / toolbar display.
    var systemImage: String {
        switch self {
        case .type(let tk):
            switch tk {
            case .class:
                "c.square"
            case .actor:
                "bolt.square"
            case .struct:
                "s.square"
            case .enum:
                "e.square"
            case .protocol, .interface:
                "p.square"
            case .trait:
                "t.square"
            case .annotation:
                "a.square"
            case .object:
                "o.square"
            case .record:
                "r.square"
            case .mixin:
                "m.square"
            case .typeAlias:
                "arrow.triangle.turn.up.right.diamond"
            case .extension:
                "curlybraces"
            case .module:
                "square.grid.3x3"
            }
        case .actor:
            "person"
        case .useCase:
            "ellipsis.rectangle"
        case .boundary:
            "rectangle.dashed"
        case .component:
            "puzzlepiece"
        case .package:
            "shippingbox"
        case .deploymentNode:
            "cube"
        case .database:
            "cylinder"
        case .artifact:
            "doc"
        case .subsystem:
            "square.stack.3d.up"
        case .entity:
            "tablecells"
        case .note:
            "note.text"
        case .lifeline:
            "arrow.down.to.line"
        case .fragment:
            "rectangle.dashed.badge.record"
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// Creates a default ``NodeContent`` for this element kind.
    func defaultContent() -> CustomDiagram.Node.Content {
        switch self {
        case .type(let tk):
                .type(.init(typeKind: tk))
        case .actor:
            .actor
        case .useCase:
            .useCase
        case .boundary:
            .boundary
        case .component:
            .component
        case .package:
            .package
        case .deploymentNode:
            .deploymentNode
        case .database:
            .database
        case .artifact:
            .artifact
        case .subsystem:
            .subsystem
        case .entity:
            .entity
        case .note:
            .note(text: "")
        case .lifeline:
            .lifeline(.object)
        case .fragment:
            .fragment(.init())
        }
    }
    // swiftlint:enable cyclomatic_complexity

    // MARK: - Catalog Grouping

    /// The catalog section this element kind belongs to.
    enum CatalogGroup: String, CaseIterable {
        case classDiagram = "Class Diagram"
        case sequenceDiagram = "Sequence Diagram"
        case useCaseDiagram = "Use Case Diagram"
        case componentDeployment = "Component / Deployment"
        case general = "General"
    }

    var catalogGroup: CatalogGroup {
        switch self {
        case .type:
            .classDiagram
        case .lifeline, .fragment:
            .sequenceDiagram
        case .actor, .useCase, .boundary:
            .useCaseDiagram
        case .component, .package, .deploymentNode,
             .database, .artifact, .subsystem:
            .componentDeployment
        case .entity, .note:
            .general
        }
    }

    /// Every element kind available in the catalog, in display order.
    static let allCases: [CustomDiagramNodeKind] = {
        var items: [CustomDiagramNodeKind] = TypeKind.allCases.map { .type($0) }
        items += [
            .lifeline, .fragment,
            .actor, .useCase, .boundary,
            .component, .package, .deploymentNode, .database, .artifact, .subsystem,
            .entity, .note
        ]
        return items
    }()

    /// Catalog items belonging to a given group.
    static func cases(in group: CatalogGroup) -> [CustomDiagramNodeKind] {
        allCases.filter { $0.catalogGroup == group }
    }
}
