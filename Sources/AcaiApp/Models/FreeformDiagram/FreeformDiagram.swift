import Foundation
import AcaiCore
import AcaiDiagram

/// A fully user-defined diagram with manually placed nodes and edges.
struct FreeformDiagram: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var nodes: [Node] = []
    var edges: [Edge] = []
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    // periphery:ignore
    var createdDate: Date = Date()
    // periphery:ignore
    var lastModified: Date = Date()
    /// Named, restorable full-state snapshots the user has saved. See `Checkpoint`.
    var checkpoints: [Checkpoint] = []

    /// The fixed icon for every freeform diagram. Freeform diagrams have no type, so the icon
    /// is a constant (mirroring how each generated `DiagramType` has its own fixed icon).
    static let systemImage = "scribble.variable"

    init(
        id: UUID = UUID(), name: String, nodes: [Node] = [], edges: [Edge] = [],
        canvasScale: Double = 1.0, canvasOffsetX: Double = 0, canvasOffsetY: Double = 0,
        createdDate: Date = Date(), lastModified: Date = Date(), checkpoints: [Checkpoint] = []
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.canvasScale = canvasScale
        self.canvasOffsetX = canvasOffsetX
        self.canvasOffsetY = canvasOffsetY
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.checkpoints = checkpoints
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, nodes, edges, canvasScale, canvasOffsetX, canvasOffsetY, createdDate, lastModified
        case checkpoints
    }

    /// Diagrams saved before checkpoints existed have no `checkpoints` key on disk — default to
    /// an empty list rather than failing to decode the whole diagram.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nodes = try container.decode([Node].self, forKey: .nodes)
        edges = try container.decode([Edge].self, forKey: .edges)
        canvasScale = try container.decode(Double.self, forKey: .canvasScale)
        canvasOffsetX = try container.decode(Double.self, forKey: .canvasOffsetX)
        canvasOffsetY = try container.decode(Double.self, forKey: .canvasOffsetY)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        checkpoints = try container.decodeIfPresent([Checkpoint].self, forKey: .checkpoints) ?? []
    }
}

extension FreeformDiagram {
    /// One placed item on a freeform canvas: an identity, a display name, the `Content` that selects
    /// how it is drawn, and a manual position (plus optional size for container kinds).
    struct Node: Identifiable, Codable, Hashable, Sendable {
        /// String id (from a UUID) so class/sequence/freeform views share one `CanvasInteraction`
        /// protocol on node identity.
        var id: String = UUID().uuidString
        var name: String
        /// What the node represents and how it is rendered (type box, actor, package, …).
        var content: Content
        /// Top-left corner position, in canvas points.
        var positionX: Double = 0
        var positionY: Double = 0
        /// User-defined size (used by resizable container nodes: package, boundary, subsystem).
        var width: Double?
        var height: Double?
        /// Draw order within its z-layer. Higher values render on top.
        var drawOrder: Int = 0

        var isResizable: Bool {
            switch content {
            case .package, .boundary, .subsystem:
                true
            default:
                false
            }
        }
    }
}

extension FreeformDiagram {
    /// A connection between two `Node`s on a freeform canvas. By default a relationship line of
    /// `kind`; carries optional `messageOrder`/`messageKind` (sequence message) or `transition`
    /// (state machine) when it represents one of those instead.
    struct Edge: Identifiable, Codable, Hashable, Sendable {
        var id: String = UUID().uuidString
        /// `id` of the `Node` the edge starts/ends at.
        var sourceNodeID: String
        var targetNodeID: String
        /// The relationship kind drawn for an ordinary edge (ignored for sequence messages).
        var kind: Relationship.Kind
        var label: String?
        /// Top-to-bottom order when this edge is a sequence-diagram message. `nil` renders it as
        /// an ordinary relationship line instead of a time-ordered message arrow.
        var messageOrder: Int?
        /// The message kind (sync/async/return/…) when `messageOrder` is set.
        var messageKind: SequenceDiagram.Message.Kind?
        /// Set when this edge is a state-machine transition between two state nodes; carries
        /// the UML `event [guard] / action` parts. `nil` for ordinary relationship edges.
        var transition: Transition?
    }
}

extension FreeformDiagram.Edge {
    /// The label parts of a state-machine transition.
    struct Transition: Codable, Hashable, Sendable {
        var event: String?
        var guardCondition: String?
        var action: String?

        /// Formats as `event [guard] / action` per UML notation (mirrors
        /// `StateDiagram.Transition.label`).
        var label: String? {
            var parts: [String] = []
            if let event, !event.isEmpty { parts.append(event) }
            if let guardCondition, !guardCondition.isEmpty { parts.append("[\(guardCondition)]") }
            if let action, !action.isEmpty { parts.append("/ \(action)") }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }
}

extension FreeformDiagram.Node {
    enum Content: Codable, Hashable, Sendable {
        /// A code type (class, struct, enum, protocol, …) with full UML class-box data.
        case type(TypeContent)
        /// An actor — typically rendered as a stick figure.
        case actor
        /// A use case — rendered as an ellipse.
        case useCase
        /// A system boundary — a labelled rectangle.
        case boundary
        /// A component — a box with a component icon.
        case component
        /// A package — a tabbed folder.
        case package
        /// A deployment node — a 3D box.
        case deploymentNode
        /// A database — a cylinder.
        case database
        /// An artifact — a document icon.
        case artifact
        /// A subsystem — like a component with «subsystem».
        case subsystem
        /// An entity — an ER entity box.
        case entity
        /// A note — a dog-eared rectangle with free-form text.
        case note(text: String)
        /// A sequence-diagram lifeline (participant header + vertical line). The associated kind
        /// carries the participant's role (object, actor, boundary, …).
        case lifeline(SequenceDiagram.Participant.Kind)
        /// A sequence-diagram combined fragment (`loop`/`alt`/`opt`/…). Its frame is derived
        /// from the message rows its operands cover, not from the node's position.
        case fragment(FragmentContent)
        /// A state-machine state. The associated kind carries the UML flavour
        /// (initial, normal, final, choice, …); the state's title is `node.name`.
        case state(StateDiagram.State.Kind)
        /// A call-graph method (or free function). The `Type.method` label is `node.name`.
        case method

        /// The element kind derived from this content.
        var kind: FreeformDiagramNodeKind {
            switch self {
            case .type(let c):
                .type(c.typeKind)
            case .lifeline:
                .lifeline
            case .fragment:
                .fragment
            case .method:
                .callGraphMethod
            case .state(let stateKind):
                .state(stateKind)
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
                .note
            }
        }

        /// The UML stereotype label (shown in «…» notation), or `nil`.
        var stereotype: String? {
            switch self {
            case .type(let c):
                c.stereotype ?? Self.defaultTypeStereotype(c.typeKind)
            case .actor:
                "actor"
            case .useCase:
                "use case"
            case .boundary:
                "boundary"
            case .component:
                "component"
            case .package:
                "package"
            case .deploymentNode:
                "node"
            case .database:
                "database"
            case .artifact:
                "artifact"
            case .subsystem:
                "subsystem"
            case .entity:
                "entity"
            case .note:
                nil
            case .lifeline(let kind):
                kind.stereotype
            case .fragment(let content):
                content.kind.rawValue
            case .state:
                nil
            case .method:
                nil
            }
        }

        private static func defaultTypeStereotype(_ typeKind: TypeKind) -> String? {
            typeKind.stereotypeString
        }
    }
}

extension FreeformDiagram.Node {
    /// Payload of a `.fragment` node: the combined-fragment operator plus its operands (guard +
    /// covered message-order span). Mirrors `SequenceDiagram.Fragment` without the identity.
    struct FragmentContent: Codable, Hashable, Sendable {
        var kind: SequenceDiagram.Fragment.Kind = .loop
        var operands: [SequenceDiagram.Fragment.Operand] = [.init(firstOrder: 1, lastOrder: 1)]
    }
}

extension FreeformDiagram.Node {
    struct TypeContent: Codable, Hashable, Sendable {
        var typeKind: TypeKind
        var stereotype: String?
        var properties: [Member] = []
        var methods: [Member] = []
        var enumCases: [EnumCase] = []
        var genericParameters: [String] = []
    }
}

extension FreeformDiagram.Node {
    struct Member: Identifiable, Codable, Hashable, Sendable {
        var id: UUID = UUID()
        var name: String
        var type: String = ""
        var accessLevel: AccessLevel = .internal
        var isStatic: Bool = false
        var isAbstract: Bool = false
        /// Legacy free-text parameter list, e.g. `"param: Type, other: Type"`. Superseded by
        /// `structuredParameters`; kept only so members saved before structured editing existed
        /// still render via `displayString`.
        var parameters: String = ""
        /// A method's parameter list. Empty for a property, and for a method never re-edited
        /// since before structured editing existed (see `parameters`).
        var structuredParameters: [Parameter] = []

        /// A single-line display string, e.g. `"name: String"` or `"doWork(input: Int): String"`.
        var displayString: String {
            var result = name
            let paramList = structuredParameters.isEmpty
                ? parameters
                : structuredParameters
                    .map { $0.type.isEmpty ? $0.name : "\($0.name): \($0.type)" }
                    .joined(separator: ", ")
            if !paramList.isEmpty {
                result += "(\(paramList))"
            }
            if !type.isEmpty {
                result += ": \(type)"
            }
            return result
        }
    }
}

extension FreeformDiagram.Node.Member {
    private enum CodingKeys: String, CodingKey {
        case id, name, type, accessLevel, isStatic, isAbstract, parameters, structuredParameters
    }

    /// Members saved before structured parameter editing existed have no `structuredParameters`
    /// key on disk — default to an empty list rather than failing to decode the whole diagram.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        accessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .accessLevel) ?? .internal
        isStatic = try container.decodeIfPresent(Bool.self, forKey: .isStatic) ?? false
        isAbstract = try container.decodeIfPresent(Bool.self, forKey: .isAbstract) ?? false
        parameters = try container.decodeIfPresent(String.self, forKey: .parameters) ?? ""
        structuredParameters = try container.decodeIfPresent([FreeformDiagram.Node.Parameter].self,
                                                               forKey: .structuredParameters) ?? []
    }
}

extension FreeformDiagram.Node {
    /// One parameter of a method member: a name and a type, e.g. `input: Int`.
    struct Parameter: Codable, Hashable, Sendable {
        var name: String
        var type: String
    }
}

extension FreeformDiagram.Node {
    struct EnumCase: Identifiable, Codable, Hashable, Sendable {
        var id: UUID = UUID()
        var name: String
        var associatedValues: String = ""
    }
}
