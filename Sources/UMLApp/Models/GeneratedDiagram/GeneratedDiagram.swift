import Foundation
import UMLCore
import UMLDiagram
import UMLRender

struct GeneratedDiagram: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// `true` once the user has manually renamed the diagram. While `false`, the name is kept in
    /// sync with the configuration (see `autoName(codebaseName:)`); a manual rename freezes it.
    var isNameUserDefined: Bool = false
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
}

extension GeneratedDiagram {
    /// The diagram's type paired with its type-specific configuration.
    enum Content: Codable, Hashable, Sendable {
        case classDiagram(ClassDiagramConfiguration)
        case sequenceDiagram(SequenceDiagramConfiguration)
        /// `nil` = not configured yet (the diagram exists but its state-variable spec
        /// has not been chosen). A configured diagram carries its `StateDiagramConfiguration`.
        case stateDiagram(StateDiagramConfiguration?)
        case useCaseDiagram
        case packageDiagram
        /// The call graph's scope (which methods are treated as callers). Defaults to the whole
        /// codebase; carried so a future scope picker can persist a type/module focus.
        case callGraph(CallGraphScope)

        /// Default content for a freshly created diagram of the given type: each kind gets its
        /// own default configuration (none is privileged over the others).
        init(type: DiagramType) {
            switch type {
            case .classDiagram:
                self = .classDiagram(.init())
            case .sequenceDiagram:
                self = .sequenceDiagram(.init(entryTypeName: "", entryMethodName: ""))
            case .stateDiagram:
                self = .stateDiagram(nil)
            case .useCaseDiagram:
                self = .useCaseDiagram
            case .packageDiagram:
                self = .packageDiagram
            case .callGraph:
                self = .callGraph(.wholeCodebase)
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
            case .packageDiagram:
                .packageDiagram
            case .callGraph:
                .callGraph
            }
        }
    }

    /// The diagram type, derived from `content`.
    var type: DiagramType { content.type }

    /// The name derived from the diagram's configuration, e.g. `"MyApp — Sequence: Foo.bar"`.
    /// Used while `isNameUserDefined` is `false` so the name tracks configuration changes.
    func autoName(codebaseName: String) -> String {
        let prefix = codebaseName.isEmpty ? "" : "\(codebaseName) — "
        switch content {
        case .sequenceDiagram(let config):
            return "\(prefix)Sequence: \(config.entryTypeName).\(config.entryMethodName)"
        case .stateDiagram(let config?):
            let variable = config.typeName.map { "\($0).\(config.variableName)" } ?? config.variableName
            return "\(prefix)State: \(variable)"
        default:
            return "\(prefix)\(content.type.displayName)"
        }
    }

    /// The class-diagram configuration, when this is a class diagram.
    var classConfiguration: ClassDiagramConfiguration? {
        get {
            if case .classDiagram(let config) = content { config } else { nil }
        }
        set {
            if let newValue, case .classDiagram = content { content = .classDiagram(newValue) }
        }
    }

    /// The sequence configuration, when this is a sequence diagram.
    var sequenceConfiguration: SequenceDiagramConfiguration? {
        get {
            if case .sequenceDiagram(let config) = content { config } else { nil }
        }
        set {
            if let newValue, case .sequenceDiagram = content { content = .sequenceDiagram(newValue) }
        }
    }

    /// The state configuration, when this is a (configured) state diagram.
    var stateConfiguration: StateDiagramConfiguration? {
        get {
            if case .stateDiagram(let config) = content { config } else { nil }
        }
        set {
            if case .stateDiagram = content { content = .stateDiagram(newValue) }
        }
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
