import Foundation
import AcaiCore
import AcaiDiagram
import AcaiRender
import AcaiQuality

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
    /// When set, the diagram renders in delta mode: the working-tree analysis is compared against
    /// its source at this git revision and added/removed/changed elements are colour-coded.
    /// `nil` renders normally.
    ///
    /// When `comparisonBaseRef` is also set (a pull-request comparison), this instead names the
    /// "new" side — the PR's head — and both sides are historical revisions rather than one
    /// revision vs. the live working tree.
    var comparisonGitRef: String?
    /// The PR's base branch for a pull-request comparison — `comparisonGitRef`'s "old" side is
    /// resolved as their merge-base (three-dot semantics), not this branch's own tip. `nil` for the
    /// two pre-existing modes (one ref vs. the live working tree).
    var comparisonBaseRef: String?
    /// Selector filter for a package diagram — kept as a sibling field (rather than folded into
    /// `content`'s `.packageDiagram` case, which carries no payload today) so already-persisted
    /// diagrams keep decoding under `Content`'s synthesized `Codable`: adding an associated value
    /// to an existing no-payload case would change that case's JSON shape. `nil` (the default)
    /// shows every module, identical to behavior before this existed.
    var packageDiagramFilter: AcaiQuality.Selector?
    /// Selector filter for a call graph — same rationale as `packageDiagramFilter`: kept outside
    /// `content` so `.callGraph(CallGraphScope)`'s existing JSON shape never changes.
    var callGraphFilter: AcaiQuality.Selector?
    var nodePositions: [String: NodePosition] = [:]
    var nodeSizes: [String: NodeSize] = [:]
    var canvasScale: Double = 1.0
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var createdDate: Date = Date()
    var lastModified: Date = Date()
}

extension GeneratedDiagram {
    enum Content: Codable, Hashable, Sendable {
        case classDiagram(ClassDiagramConfiguration)
        case sequenceDiagram(SequenceDiagramConfiguration)
        /// `nil` = not configured yet (the diagram exists but its state-variable spec
        /// has not been chosen). A configured diagram carries its `StateDiagramConfiguration`.
        case stateDiagram(StateDiagramConfiguration?)
        case packageDiagram
        /// The call graph's scope (which methods are treated as callers). Defaults to the whole
        /// codebase; carried so a future scope picker can persist a type/module focus.
        case callGraph(CallGraphScope)
        /// Every module plotted on the Abstractness-vs-Instability chart. No configuration — it
        /// always covers every module `CodeMetrics.ModuleCoupling` reports, like `.packageDiagram`.
        case moduleCoupling
        /// Churn × complexity scatter. No configuration, for the same reason as `.moduleCoupling`.
        case hotspot

        init(type: DiagramType) {
            switch type {
            case .classDiagram:
                self = .classDiagram(.init())
            case .sequenceDiagram:
                self = .sequenceDiagram(.init(entryTypeName: "", entryMethodName: ""))
            case .stateDiagram:
                self = .stateDiagram(nil)
            case .packageDiagram:
                self = .packageDiagram
            case .callGraph:
                self = .callGraph(.wholeCodebase)
            case .moduleCoupling:
                self = .moduleCoupling
            case .hotspot:
                self = .hotspot
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
            case .packageDiagram:
                .packageDiagram
            case .callGraph:
                .callGraph
            case .moduleCoupling:
                .moduleCoupling
            case .hotspot:
                .hotspot
            }
        }
    }

    var type: DiagramType { content.type }

    /// The name derived from the diagram's configuration, e.g. `"MyApp — Sequence: Foo.bar"`.
    /// Used while `isNameUserDefined` is `false` so the name tracks configuration changes.
    func autoName(codebaseName: String) -> String {
        let prefix = codebaseName.isEmpty ? "" : "\(codebaseName) — "
        switch content {
        case .sequenceDiagram(let config):
            // A top-level-function entry has an empty type name; show just the function.
            let entry = config.entryTypeName.isEmpty
                ? config.entryMethodName
                : "\(config.entryTypeName).\(config.entryMethodName)"
            return "\(prefix)Sequence: \(entry)"
        case .stateDiagram(let config?):
            let variable = config.typeName.map { "\($0).\(config.variableName)" } ?? config.variableName
            return "\(prefix)State: \(variable)"
        case .callGraph(let scope):
            switch scope {
            case .wholeCodebase:
                return "\(prefix)Call Graph"
            case .type(let name):
                return "\(prefix)Call Graph: \(name)"
            case .module(let name):
                return "\(prefix)Call Graph: \(name)"
            }
        default:
            return "\(prefix)\(content.type.displayName)"
        }
    }

    var classConfiguration: ClassDiagramConfiguration? {
        get {
            if case .classDiagram(let config) = content { config } else { nil }
        }
        set {
            if let newValue, case .classDiagram = content { content = .classDiagram(newValue) }
        }
    }

    var sequenceConfiguration: SequenceDiagramConfiguration? {
        get {
            if case .sequenceDiagram(let config) = content { config } else { nil }
        }
        set {
            if let newValue, case .sequenceDiagram = content { content = .sequenceDiagram(newValue) }
        }
    }

    var stateConfiguration: StateDiagramConfiguration? {
        get {
            if case .stateDiagram(let config) = content { config } else { nil }
        }
        set {
            if case .stateDiagram = content { content = .stateDiagram(newValue) }
        }
    }

    var callGraphScope: CallGraphScope? {
        get {
            if case .callGraph(let scope) = content { scope } else { nil }
        }
        set {
            if let newValue, case .callGraph = content { content = .callGraph(newValue) }
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
