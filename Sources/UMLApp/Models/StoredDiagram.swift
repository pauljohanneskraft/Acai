import Foundation
import UMLCore

// MARK: - Diagram Type

enum DiagramType: String, Codable, CaseIterable, Identifiable, Sendable {
    case classDiagram = "class"
    case sequenceDiagram = "sequence"
    case stateDiagram = "state"
    case useCaseDiagram = "useCase"
    case deploymentDiagram = "deployment"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classDiagram: "Class Diagram"
        case .sequenceDiagram: "Sequence Diagram"
        case .stateDiagram: "State Diagram"
        case .useCaseDiagram: "Use Case Diagram"
        case .deploymentDiagram: "Deployment Diagram"
        }
    }

    var systemImage: String {
        switch self {
        case .classDiagram: "rectangle.3.group"
        case .sequenceDiagram: "arrow.right.arrow.left"
        case .stateDiagram: "circle.hexagonpath"
        case .useCaseDiagram: "person.3"
        case .deploymentDiagram: "server.rack"
        }
    }
}

// MARK: - Diagram Configuration

struct DiagramConfiguration: Codable, Hashable, Sendable {
    var showProperties: Bool = true
    var showMethods: Bool = true
    var showEnumCases: Bool = true
    var showRelationships: Bool = true
    var showInheritance: Bool = true
    var showComposition: Bool = true
    var showDependency: Bool = true
    var groupByDirectory: Bool = true
    var showExternalTypes: Bool = false
    /// Access level filter — only show members at or above this level.
    var minimumAccessLevel: AccessLevel?
    /// When `true`, hides types originating from Dart generated files
    /// (e.g. `*.freezed.dart`, `*.g.dart`) as well as types whose names
    /// match common code-generation patterns.
    var hideGeneratedDartTypes: Bool = true
}

// MARK: - Stored Node Position

struct StoredNodePosition: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Stored Node Size

struct StoredNodeSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(size: CGSize) {
        self.width = Double(size.width)
        self.height = Double(size.height)
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

// MARK: - Stored Diagram

/// A generated diagram that is persisted on disk, linked to a codebase.
/// Can be regenerated when the underlying code changes.
struct StoredDiagram: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var type: DiagramType
    var codebaseID: UUID
    var configuration: DiagramConfiguration
    var nodePositions: [String: StoredNodePosition] = [:]
    /// User-overridden node sizes (from resize handles).
    var nodeSizes: [String: StoredNodeSize] = [:]
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var createdDate: Date = Date()
    var lastModified: Date = Date()
}

// MARK: - Node Content

/// Type-specific payload of a custom diagram node.
///
/// Only `.type` nodes carry members, enum cases, or generic parameters.
/// All other UML element kinds carry at most a small amount of data
/// (e.g. a note carries its free-form text).
enum NodeContent: Codable, Hashable, Sendable {
    /// A code type (class, struct, enum, protocol, …) with full UML class-box data.
    case type(TypeNodeContent)
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

    /// The element kind derived from this content.
    var elementKind: DiagramElementKind {
        switch self {
        case .type(let c):    .type(c.typeKind)
        case .actor:          .actor
        case .useCase:        .useCase
        case .boundary:       .boundary
        case .component:      .component
        case .package:        .package
        case .deploymentNode: .deploymentNode
        case .database:       .database
        case .artifact:       .artifact
        case .subsystem:      .subsystem
        case .entity:         .entity
        case .note:           .note
        }
    }

    /// The UML stereotype label (shown in «…» notation), or `nil`.
    var stereotype: String? {
        switch self {
        case .type(let c):
            c.stereotype ?? Self.defaultTypeStereotype(c.typeKind)
        case .actor:          "actor"
        case .useCase:        "use case"
        case .boundary:       "boundary"
        case .component:      "component"
        case .package:        "package"
        case .deploymentNode: "node"
        case .database:       "database"
        case .artifact:       "artifact"
        case .subsystem:      "subsystem"
        case .entity:         "entity"
        case .note:           nil
        }
    }

    private static func defaultTypeStereotype(_ typeKind: TypeKind) -> String? {
        typeKind.stereotypeString
    }
}

/// Content data specific to code-type nodes (class, struct, enum, protocol, …).
struct TypeNodeContent: Codable, Hashable, Sendable {
    var typeKind: TypeKind
    /// Custom stereotype override — when `nil`, the default based on `typeKind` is used.
    var stereotype: String?
    var properties: [CustomMember] = []
    var methods: [CustomMember] = []
    var enumCases: [CustomEnumCase] = []
    var genericParameters: [String] = []
}

struct CustomMember: Identifiable, Codable, Hashable, Sendable {
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

struct CustomEnumCase: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var associatedValues: String = ""
}

// MARK: - Custom Diagram Node

/// A user-defined node in a custom diagram.
///
/// Shared properties live directly on the node (id, name, position).
/// Kind-specific data is inside ``content``.
struct CustomDiagramNode: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var content: NodeContent
    var positionX: Double = 0
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
        case .package, .boundary, .subsystem: true
        default: false
        }
    }
}

// MARK: - Custom Diagram Edge

/// A user-defined edge in a custom diagram.
struct CustomDiagramEdge: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var sourceNodeID: UUID
    var targetNodeID: UUID
    var kind: Relationship.Kind
    var label: String?
}

// MARK: - Custom Diagram

/// A fully user-defined diagram with manually placed nodes and edges.
/// Ownership: belongs to a project (via `ownerProjectID`).
struct CustomDiagram: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var diagramType: DiagramType = .classDiagram
    var ownerProjectID: UUID?
    var nodes: [CustomDiagramNode] = []
    var edges: [CustomDiagramEdge] = []
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var createdDate: Date = Date()
    var lastModified: Date = Date()
}
