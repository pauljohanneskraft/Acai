import Foundation
import AcaiCore
import AcaiDiagram

enum FreeformDiagramNodeKind: Equatable, Hashable, Sendable, Identifiable {

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

    // MARK: - Per-Shape Metadata

    /// Every catalogue fact about a shape — identity, display name, icon, grouping — derived
    /// from one exhaustive switch. A new case must fill in all four here before the enum
    /// compiles, rather than risk a shape that only picked up some of them because a separate
    /// switch elsewhere was never visited.
    private struct Metadata {
        let id: String
        let displayName: String
        let systemImage: String
        let catalogGroup: CatalogGroup
    }

    private var metadata: Metadata {
        switch self {
        case .type(let tk):
            let displayName: String
            let systemImage: String
            switch tk {
            case .class:
                displayName = "Class"
                systemImage = "c.square"
            case .actor:
                displayName = "Actor"
                systemImage = "bolt.square"
            case .struct:
                displayName = "Struct"
                systemImage = "s.square"
            case .enum:
                displayName = "Enum"
                systemImage = "e.square"
            case .protocol:
                displayName = "Protocol"
                systemImage = "p.square"
            case .interface:
                displayName = "Interface"
                systemImage = "p.square"
            case .trait:
                displayName = "Trait"
                systemImage = "t.square"
            case .typeAlias:
                displayName = "Type Alias"
                systemImage = "arrow.triangle.turn.up.right.diamond"
            case .object:
                displayName = "Object"
                systemImage = "o.square"
            case .extension:
                displayName = "Extension"
                systemImage = "curlybraces"
            case .annotation:
                displayName = "Annotation"
                systemImage = "a.square"
            case .module:
                displayName = "Module"
                systemImage = "square.grid.3x3"
            case .record:
                displayName = "Record"
                systemImage = "r.square"
            case .mixin:
                displayName = "Mixin"
                systemImage = "m.square"
            }
            return Metadata(
                id: "type.\(tk.rawValue)", displayName: displayName, systemImage: systemImage,
                catalogGroup: .classDiagram
            )
        case .state(let sk):
            let displayName: String
            let systemImage: String
            switch sk {
            case .initial:
                displayName = "Initial State"
                systemImage = "circle.fill"
            case .final:
                displayName = "Final State"
                systemImage = "circle.circle"
            case .choice:
                displayName = "Choice"
                systemImage = "diamond"
            case .fork:
                displayName = "Fork"
                systemImage = "minus.rectangle"
            case .join:
                displayName = "Join"
                systemImage = "minus.rectangle"
            case .normal, .composite:
                displayName = "State"
                systemImage = "capsule"
            }
            return Metadata(
                id: "state.\(sk.rawValue)", displayName: displayName, systemImage: systemImage,
                catalogGroup: .stateDiagram
            )
        case .actor:
            return Metadata(id: "actor", displayName: "Actor", systemImage: "person", catalogGroup: .useCaseDiagram)
        case .useCase:
            return Metadata(
                id: "useCase", displayName: "Use Case", systemImage: "ellipsis.rectangle",
                catalogGroup: .useCaseDiagram
            )
        case .boundary:
            return Metadata(
                id: "boundary", displayName: "Boundary", systemImage: "rectangle.dashed",
                catalogGroup: .useCaseDiagram
            )
        case .component:
            return Metadata(
                id: "component", displayName: "Component", systemImage: "puzzlepiece",
                catalogGroup: .componentDeployment
            )
        case .package:
            return Metadata(
                id: "package", displayName: "Package", systemImage: "shippingbox",
                catalogGroup: .componentDeployment
            )
        case .deploymentNode:
            return Metadata(
                id: "deploymentNode", displayName: "Node", systemImage: "cube",
                catalogGroup: .componentDeployment
            )
        case .database:
            return Metadata(
                id: "database", displayName: "Database", systemImage: "cylinder",
                catalogGroup: .componentDeployment
            )
        case .artifact:
            return Metadata(
                id: "artifact", displayName: "Artifact", systemImage: "doc",
                catalogGroup: .componentDeployment
            )
        case .subsystem:
            return Metadata(
                id: "subsystem", displayName: "Subsystem", systemImage: "square.stack.3d.up",
                catalogGroup: .componentDeployment
            )
        case .entity:
            return Metadata(id: "entity", displayName: "Entity", systemImage: "tablecells", catalogGroup: .general)
        case .note:
            return Metadata(id: "note", displayName: "Note", systemImage: "note.text", catalogGroup: .general)
        case .lifeline:
            return Metadata(
                id: "lifeline", displayName: "Lifeline", systemImage: "arrow.down.to.line",
                catalogGroup: .sequenceDiagram
            )
        case .fragment:
            return Metadata(
                id: "fragment", displayName: "Fragment (loop/alt/opt)",
                systemImage: "rectangle.dashed.badge.record", catalogGroup: .sequenceDiagram
            )
        case .callGraphMethod:
            return Metadata(
                id: "callGraphMethod", displayName: "Method", systemImage: "function",
                catalogGroup: .callGraph
            )
        }
    }

    // MARK: - Identifiable

    var id: String { metadata.id }

    // MARK: - Display Helpers

    var displayName: String { metadata.displayName }

    var systemImage: String { metadata.systemImage }

    /// A default name for a freshly inserted node of this kind, e.g. `"NewClass"` for `.type(.class)`
    /// or `"NewNote"` for `.note` — shared by every insertion path (drag-drop, context menu,
    /// point-and-place) so they all name a new node identically.
    var defaultNodeName: String {
        "New" + displayName
            .replacingOccurrences(of: " / ", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Catalog Grouping

    enum CatalogGroup: String, CaseIterable {
        case classDiagram = "Class Diagram"
        case sequenceDiagram = "Sequence Diagram"
        case stateDiagram = "State Diagram"
        case callGraph = "Call Graph"
        case useCaseDiagram = "Use Case Diagram"
        case componentDeployment = "Component / Deployment"
        case general = "General"
    }

    var catalogGroup: CatalogGroup { metadata.catalogGroup }

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
