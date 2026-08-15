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
        case packageDiagram
        /// The call graph's scope (which methods are treated as callers). Defaults to the whole
        /// codebase; carried so a future scope picker can persist a type/module focus.
        case callGraph(CallGraphScope)
        /// Every module plotted on the Abstractness-vs-Instability chart. No configuration — it
        /// always covers every module `CodeMetrics.ModuleCoupling` reports, like `.packageDiagram`.
        case moduleCoupling
        /// Churn × complexity scatter. No configuration, for the same reason as `.moduleCoupling`.
        case hotspot
        /// One isolated dependency cycle, identified by the scope/members `AcaiQuality
        /// .CycleFinder` already reported for it — see `CycleDiagramReference`.
        case cycleDiagram(CycleDiagramReference)

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
            case .packageDiagram:
                self = .packageDiagram
            case .callGraph:
                self = .callGraph(.wholeCodebase)
            case .moduleCoupling:
                self = .moduleCoupling
            case .hotspot:
                self = .hotspot
            case .cycleDiagram:
                // Degenerate/unreachable by design: a cycle diagram has no meaningful content until
                // a specific cycle is chosen, so it's never created through this generic
                // type-only initializer — `CodebaseDetailView.diagramsBar` excludes `.cycleDiagram`
                // from the general "add a diagram" grid, and the one real entry point (a Quality
                // Check cycle violation's "View as Diagram" action) constructs
                // `.cycleDiagram(CycleDiagramReference(...))` directly with the real scope/members.
                self = .cycleDiagram(CycleDiagramReference(scope: "types", members: []))
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
            case .cycleDiagram:
                .cycleDiagram
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
        case .cycleDiagram(let reference):
            let shown = reference.members.prefix(3).joined(separator: " ↔ ")
            let suffix = reference.members.count > 3 ? "…" : ""
            return "\(prefix)Cycle: \(shown)\(suffix)"
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

    /// The call-graph scope, when this is a call graph.
    var callGraphScope: CallGraphScope? {
        get {
            if case .callGraph(let scope) = content { scope } else { nil }
        }
        set {
            if let newValue, case .callGraph = content { content = .callGraph(newValue) }
        }
    }

    /// The isolated cycle's scope/members, when this is a cycle diagram.
    var cycleDiagramReference: CycleDiagramReference? {
        if case .cycleDiagram(let reference) = content { reference } else { nil }
    }
}

/// Identifies exactly one `AcaiQuality.CycleFinder.Cycle` for a Cycle Diagram to isolate and
/// render: which scope it was found at, and its members (type ids for a `.types`-scope cycle,
/// module names for a `.modules`-scope one), in the same order `CycleFinder` itself reports them.
/// Stores `scope` as `AcaiQuality.CycleFinder.Scope`'s plain `rawValue` rather than the enum type
/// itself — `AcaiApp` already depends on `AcaiQuality`, but keeping this reference a plain,
/// self-contained value (matching how it's actually produced, straight out of `Violation.detail["scope"]`
/// and `Violation.subject`) avoids coupling `GeneratedDiagram.Content`'s Codable shape to another
/// module's enum layout.
struct CycleDiagramReference: Codable, Hashable, Sendable {
    /// `AcaiQuality.CycleFinder.Scope.modules.rawValue` or `.types.rawValue` ("modules"/"types").
    var scope: String
    /// The cycle's members, sorted (mirrors `CycleFinder.Cycle.members`) — type ids for a
    /// `.types`-scope cycle, module names for a `.modules`-scope one.
    var members: [String]
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
