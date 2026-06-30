import UMLCore
import UMLDiagram

/// Identifies the kind of element in a freeform diagram.
///
/// Used for **catalog selection** (picking which element to add) and **display logic**
/// (icons, colours, labels). The actual per-node data lives in ``NodeContent``.
enum FreeformDiagramNodeKind: Equatable, Hashable, Sendable, Identifiable {

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
    /// freeform diagram, and available in the catalog for building sequence diagrams by hand.
    case lifeline
    /// A sequence-diagram combined fragment (`loop`/`alt`/`opt`/…) framing a span of messages.
    case fragment

    // MARK: - State Diagram Elements

    /// A state-machine state. The associated `StateDiagram.State.Kind` carries the UML
    /// flavour; the catalog offers `.normal`, `.initial`, `.final` and `.choice`.
    case state(StateDiagram.State.Kind)

    // MARK: - Call Graph Elements

    /// A call-graph method (or free function). Created when a call graph is saved as a freeform
    /// diagram, and available in the catalog for sketching call graphs by hand. The `Type.method`
    /// label is the node's name.
    case callGraphMethod

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .type(let tk):
            "type.\(tk.rawValue)"
        case .state(let sk):
            "state.\(sk.rawValue)"
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
        case .callGraphMethod:
            "callGraphMethod"
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
        case .callGraphMethod:
            "Method"
        case .state(let sk):
            switch sk {
            case .initial:
                "Initial State"
            case .final:
                "Final State"
            case .choice:
                "Choice"
            case .fork:
                "Fork"
            case .join:
                "Join"
            case .normal, .composite:
                "State"
            }
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
        case .callGraphMethod:
            "function"
        case .state(let sk):
            switch sk {
            case .initial:
                "circle.fill"
            case .final:
                "circle.circle"
            case .choice:
                "diamond"
            case .fork, .join:
                "minus.rectangle"
            case .normal, .composite:
                "capsule"
            }
        }
    }

    // MARK: - Catalog Grouping

    /// The catalog section this element kind belongs to.
    enum CatalogGroup: String, CaseIterable {
        case classDiagram = "Class Diagram"
        case sequenceDiagram = "Sequence Diagram"
        case stateDiagram = "State Diagram"
        case callGraph = "Call Graph"
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
        case .state:
            .stateDiagram
        case .callGraphMethod:
            .callGraph
        case .actor, .useCase, .boundary:
            .useCaseDiagram
        case .component, .package, .deploymentNode,
             .database, .artifact, .subsystem:
            .componentDeployment
        case .entity, .note:
            .general
        }
    }

    /// Every element kind available in the catalog, in display order. State kinds are
    /// limited to the flavours generated diagrams produce (no fork/join/composite yet).
    static let allCases: [FreeformDiagramNodeKind] = {
        var items: [FreeformDiagramNodeKind] = TypeKind.allCases.map { .type($0) }
        items += [
            .lifeline, .fragment,
            .state(.normal), .state(.initial), .state(.final), .state(.choice),
            .callGraphMethod,
            .actor, .useCase, .boundary,
            .component, .package, .deploymentNode, .database, .artifact, .subsystem,
            .entity, .note
        ]
        return items
    }()

    /// Catalog items belonging to a given group.
    static func cases(in group: CatalogGroup) -> [FreeformDiagramNodeKind] {
        allCases.filter { $0.catalogGroup == group }
    }
}

extension FreeformDiagram.Node.Content {
    // swiftlint:disable cyclomatic_complexity
    /// The default content for a newly-added element of `kind`. Lives on `Content` — rather than as
    /// `FreeformDiagramNodeKind.defaultContent()` — so the kind enum does not depend on `Content`,
    /// breaking the `Content ↔ FreeformDiagramNodeKind` reference cycle (`Content.kind` is the other
    /// direction).
    static func makeDefault(for kind: FreeformDiagramNodeKind) -> FreeformDiagram.Node.Content {
        switch kind {
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
        case .callGraphMethod:
            .method
        case .state(let sk):
            .state(sk)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
