import Foundation
import UMLCore
import UMLDiagram

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

    /// The fixed icon for every freeform diagram. Freeform diagrams have no type, so the icon
    /// is a constant (mirroring how each generated `DiagramType` has its own fixed icon).
    static let systemImage = "scribble.variable"
}

extension FreeformDiagram {
    /// One placed item on a freeform canvas: an identity, a display name, the `Content` that selects
    /// how it is drawn, and a manual position (plus optional size for container kinds).
    struct Node: Identifiable, Codable, Hashable, Sendable {
        /// String id (generated from a UUID, so still collision-free). Shared `String` node
        /// identity lets the class/sequence/freeform views use one `CanvasInteraction` protocol.
        var id: String = UUID().uuidString
        /// The node's display label.
        var name: String
        /// What the node represents and how it is rendered (type box, actor, package, …).
        var content: Content
        /// Manual x position of the node's top-left corner, in canvas points.
        var positionX: Double = 0
        /// Manual y position of the node's top-left corner, in canvas points.
        var positionY: Double = 0
        /// User-defined width (used by resizable container nodes: package, boundary, subsystem).
        var width: Double?
        /// User-defined height (used by resizable container nodes: package, boundary, subsystem).
        var height: Double?
        /// Draw order within its z-layer. Higher values render on top.
        var drawOrder: Int = 0

        /// Whether this node should display resize handles.
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
        /// Stable edge identity (UUID-derived string).
        var id: String = UUID().uuidString
        /// `id` of the `Node` the edge starts at.
        var sourceNodeID: String
        /// `id` of the `Node` the edge ends at.
        var targetNodeID: String
        /// The relationship kind drawn for an ordinary edge (ignored for sequence messages).
        var kind: Relationship.Kind
        /// Optional text label shown on the edge.
        var label: String?
        /// Top-to-bottom order when this edge is a sequence-diagram message. `nil` for ordinary
        /// relationship edges, which renders the edge as a relationship line instead of a
        /// time-ordered message arrow.
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
        var parameters: String = "" // For methods: "(param: Type, ...)"

        /// A single-line display string for the member, e.g. "name: String" or "doWork(input: Int): String".
        var displayString: String {
            var result = name
            if !parameters.isEmpty {
                result += "(\(parameters))"
            }
            if !type.isEmpty {
                result += ": \(type)"
            }
            return result
        }
    }
}

extension FreeformDiagram.Node.Member {
    /// Parse a property line like `"name: String"` — the inverse of `displayString` for a
    /// property. Splits on the first colon and trims both sides; a missing type becomes `""`.
    init(propertyText: String) {
        let parts = propertyText.split(separator: ":", maxSplits: 1)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces)
            ?? propertyText.trimmingCharacters(in: .whitespaces)
        let type = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        self.init(name: name, type: type)
    }

    /// Parse a method line like `"doWork(input: Int): String"` — the inverse of `displayString`
    /// for a method. Falls back to a bare `name: Type` (no parens) or just a name.
    init(methodText: String) {
        let trimmed = methodText.trimmingCharacters(in: .whitespaces)
        var name = trimmed
        var parameters = ""
        var returnType = ""
        if let parenStart = trimmed.firstIndex(of: "("),
           let parenEnd = trimmed.firstIndex(of: ")") {
            name = String(trimmed[trimmed.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
            parameters = String(trimmed[trimmed.index(after: parenStart)..<parenEnd])
            let afterParen = trimmed[trimmed.index(after: parenEnd)...]
            if let colonIdx = afterParen.firstIndex(of: ":") {
                returnType = String(afterParen[afterParen.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        } else if let colonIdx = trimmed.firstIndex(of: ":") {
            name = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            returnType = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
        }
        self.init(name: name, type: returnType, parameters: parameters)
    }
}

extension FreeformDiagram.Node {
    struct EnumCase: Identifiable, Codable, Hashable, Sendable {
        var id: UUID = UUID()
        var name: String
        var associatedValues: String = ""
    }
}
