import UMLCore

/// Identifies the kind of element in a custom diagram.
///
/// Used for **catalog selection** (picking which element to add) and **display logic**
/// (icons, colours, labels). The actual per-node data lives in ``NodeContent``.
enum DiagramElementKind: Equatable, Hashable, Sendable, Identifiable {

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
        }
    }

    /// SF Symbol name for catalog / toolbar display.
    var systemImage: String {
        switch self {
        case .type(let tk):
            switch tk {
            case .class:
                "c.square"
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
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// Creates a default ``NodeContent`` for this element kind.
    func defaultContent() -> NodeContent {
        switch self {
        case .type(let tk):
            .type(TypeNodeContent(typeKind: tk))
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
        }
    }
    // swiftlint:enable cyclomatic_complexity

    // MARK: - Catalog Grouping

    /// The catalog section this element kind belongs to.
    enum CatalogGroup: String, CaseIterable {
        case classDiagram = "Class Diagram"
        case useCaseDiagram = "Use Case Diagram"
        case componentDeployment = "Component / Deployment"
        case general = "General"
    }

    var catalogGroup: CatalogGroup {
        switch self {
        case .type:
            .classDiagram
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
    static let allCatalogItems: [DiagramElementKind] = {
        var items: [DiagramElementKind] = TypeKind.allCases.map { .type($0) }
        items += [
            .actor, .useCase, .boundary,
            .component, .package, .deploymentNode, .database, .artifact, .subsystem,
            .entity, .note
        ]
        return items
    }()

    /// Catalog items belonging to a given group.
    static func catalogItems(in group: CatalogGroup) -> [DiagramElementKind] {
        allCatalogItems.filter { $0.catalogGroup == group }
    }
}
