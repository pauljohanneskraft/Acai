import Foundation
import UMLCore
import UMLRender

struct GeneratedDiagram: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// The diagram's type together with its type-specific configuration. A single enum carries
    /// both the kind and its settings, so each new configurable type adds exactly one case here
    /// instead of a separate optional property per type.
    var content: Content
    var codebaseID: UUID
    var nodePositions: [String: NodePosition] = [:]
    /// User-overridden node sizes (from resize handles).
    var nodeSizes: [String: NodeSize] = [:]
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var createdDate: Date = Date()
    var lastModified: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        content: Content,
        codebaseID: UUID
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.codebaseID = codebaseID
    }

    /// Convenience for the class/state/use-case/deployment path, which is keyed by `DiagramType`
    /// plus the shared class-diagram configuration.
    init(
        id: UUID = UUID(),
        name: String,
        type: DiagramType,
        codebaseID: UUID,
        configuration: Configuration
    ) {
        self.init(
            id: id,
            name: name,
            content: Content(type: type, configuration: configuration),
            codebaseID: codebaseID
        )
    }
}

extension GeneratedDiagram {
    /// The diagram's type paired with its type-specific configuration.
    enum Content: Hashable, Sendable {
        case classDiagram(DiagramConfiguration)
        case sequenceDiagram(SequenceConfiguration)
        case stateDiagram
        case useCaseDiagram
        case deploymentDiagram

        /// Builds the content for a `DiagramType`, attaching the class configuration where the
        /// type uses it. Used by the generic generated-diagram creation path.
        init(type: DiagramType, configuration: DiagramConfiguration) {
            switch type {
            case .classDiagram:
                self = .classDiagram(configuration)
            case .sequenceDiagram:
                self = .sequenceDiagram(SequenceConfiguration(entryTypeName: "", entryMethodName: ""))
            case .stateDiagram:
                self = .stateDiagram
            case .useCaseDiagram:
                self = .useCaseDiagram
            case .deploymentDiagram:
                self = .deploymentDiagram
            }
        }

        var type: DiagramType {
            switch self {
            case .classDiagram:
                .classDiagram
            case .sequenceDiagram:
                .sequenceDiagram
            case .stateDiagram:
                .stateDiagram
            case .useCaseDiagram:
                .useCaseDiagram
            case .deploymentDiagram:
                .deploymentDiagram
            }
        }
    }

    /// The diagram type, derived from `content`.
    var type: DiagramType { content.type }

    /// The shared rendering configuration. Meaningful for class diagrams; other types return a
    /// default (read) and ignore writes that don't apply to them.
    var configuration: Configuration {
        get {
            if case .classDiagram(let config) = content { config } else { .init() }
        }
        set {
            if case .classDiagram = content { content = .classDiagram(newValue) }
        }
    }

    /// The sequence configuration, when this is a sequence diagram.
    var sequenceConfiguration: SequenceConfiguration? {
        get {
            if case .sequenceDiagram(let config) = content { config } else { nil }
        }
        set {
            if let newValue { content = .sequenceDiagram(newValue) }
        }
    }

    /// Describes how a sequence diagram is traced from the codebase: the starting method, how
    /// deep to follow calls, and how abstract receiver types resolve to concrete ones.
    struct SequenceConfiguration: Codable, Hashable, Sendable {
        var entryTypeName: String
        var entryMethodName: String
        var maxDepth: Int = 5
        /// Maps protocol/interface names to the concrete type whose body should be followed.
        var typeMapping: [String: String] = [:]
    }
}

extension GeneratedDiagram {
    /// The diagram's rendering configuration. The type itself lives in `UMLRender`
    /// (shared with the CLI image renderer); this alias keeps the historical
    /// `GeneratedDiagram.Configuration` spelling used throughout the app.
    typealias Configuration = DiagramConfiguration
}

// MARK: - Codable

extension GeneratedDiagram: Codable {
    // Persisted as a flat `{ type, configuration?, sequenceConfiguration? }` shape, matching the
    // pre-`content` on-disk format so existing class diagrams keep loading. `content` is the
    // in-memory source of truth; encoding/decoding bridges to and from the flat fields.
    private enum CodingKeys: String, CodingKey {
        case id, name, type, configuration, sequenceConfiguration, codebaseID
        case nodePositions, nodeSizes, canvasScale, canvasOffsetX, canvasOffsetY
        case createdDate, lastModified
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let codebaseID = try container.decode(UUID.self, forKey: .codebaseID)
        let type = (try? container.decode(DiagramType.self, forKey: .type)) ?? .classDiagram

        let content: Content
        switch type {
        case .classDiagram:
            content = .classDiagram(
                (try? container.decode(Configuration.self, forKey: .configuration)) ?? .init()
            )
        case .sequenceDiagram:
            content = .sequenceDiagram(
                (try? container.decode(SequenceConfiguration.self, forKey: .sequenceConfiguration))
                    ?? SequenceConfiguration(entryTypeName: "", entryMethodName: "")
            )
        case .stateDiagram:
            content = .stateDiagram
        case .useCaseDiagram:
            content = .useCaseDiagram
        case .deploymentDiagram:
            content = .deploymentDiagram
        }

        self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            name: name,
            content: content,
            codebaseID: codebaseID
        )
        nodePositions = (try? container.decode([String: NodePosition].self, forKey: .nodePositions)) ?? [:]
        nodeSizes = (try? container.decode([String: NodeSize].self, forKey: .nodeSizes)) ?? [:]
        canvasScale = (try? container.decode(Double.self, forKey: .canvasScale)) ?? 1.0
        canvasOffsetX = (try? container.decode(Double.self, forKey: .canvasOffsetX)) ?? 0
        canvasOffsetY = (try? container.decode(Double.self, forKey: .canvasOffsetY)) ?? 0
        createdDate = (try? container.decode(Date.self, forKey: .createdDate)) ?? Date()
        lastModified = (try? container.decode(Date.self, forKey: .lastModified)) ?? Date()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        switch content {
        case .classDiagram(let config):
            try container.encode(config, forKey: .configuration)
        case .sequenceDiagram(let config):
            try container.encode(config, forKey: .sequenceConfiguration)
        case .stateDiagram, .useCaseDiagram, .deploymentDiagram:
            break
        }
        try container.encode(codebaseID, forKey: .codebaseID)
        try container.encode(nodePositions, forKey: .nodePositions)
        try container.encode(nodeSizes, forKey: .nodeSizes)
        try container.encode(canvasScale, forKey: .canvasScale)
        try container.encode(canvasOffsetX, forKey: .canvasOffsetX)
        try container.encode(canvasOffsetY, forKey: .canvasOffsetY)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastModified, forKey: .lastModified)
    }
}

extension GeneratedDiagram {
    struct NodePosition: Codable, Hashable, Sendable {
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
}

extension GeneratedDiagram {
    struct NodeSize: Codable, Hashable, Sendable {
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
}
