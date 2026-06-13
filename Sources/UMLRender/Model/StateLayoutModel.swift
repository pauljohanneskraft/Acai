import CoreGraphics
import Foundation
import UMLCore
import UMLDiagram

/// Computes node frames and edge routes for a `StateDiagram`.
///
/// States and transitions form a plain directed graph, so layout delegates to
/// the shared `SugiyamaLayoutEngine`: transitions are fed as `.inheritance`
/// edges, which `LayerAssignment` layers along — the initial pseudo-state has no
/// incoming edges and becomes the root, giving a top-down flow. Only node sizing
/// and edge labels are state-specific.
public struct StateLayoutModel: Sendable {

    public struct NodeFrame: Identifiable, Sendable {
        public let id: String
        public let state: StateDiagram.State
        public let rect: CGRect
    }

    public struct EdgeLayout: Identifiable, Sendable {
        public let id: Int
        public let from: String
        public let to: String
        public let label: String?
    }

    public let nodes: [NodeFrame]
    public let edges: [EdgeLayout]
    public let contentSize: CGSize

    private let framesByID: [String: CGRect]

    /// Lays out `diagram`, with `positionOverrides` (state-id → centre) taking
    /// precedence over computed positions — used to restore user drags.
    public init(diagram: StateDiagram, positionOverrides: [String: CGPoint] = [:]) {
        let sizes = Dictionary(
            diagram.states.map { ($0.id, Self.estimatedSize(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )

        let inputs = diagram.states.map {
            SugiyamaLayoutEngine.NodeInput(id: $0.id, size: sizes[$0.id] ?? .zero, group: nil)
        }
        // `LayerAssignment` puts inheritance *targets* in the top layer, so feed
        // each transition reversed: its origin state is the "parent", which
        // places the initial pseudo-state at the top and flows downward.
        let edgeInputs = diagram.transitions.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.to, targetID: $0.from, kind: .inheritance)
        }
        var positions = SugiyamaLayoutEngine().layout(nodes: inputs, edges: edgeInputs).positions
        for (id, point) in positionOverrides {
            positions[id] = point
        }

        // Normalize so the content's top-left corner sits at the origin.
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        for state in diagram.states {
            let size = sizes[state.id] ?? .zero
            let center = positions[state.id] ?? .zero
            minX = min(minX, center.x - size.width / 2)
            minY = min(minY, center.y - size.height / 2)
        }
        if minX == .greatestFiniteMagnitude { minX = 0 }
        if minY == .greatestFiniteMagnitude { minY = 0 }

        var frames: [String: CGRect] = [:]
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        var nodeFrames: [NodeFrame] = []
        for state in diagram.states {
            let size = sizes[state.id] ?? .zero
            let center = positions[state.id] ?? .zero
            let rect = CGRect(
                x: center.x - size.width / 2 - minX,
                y: center.y - size.height / 2 - minY,
                width: size.width,
                height: size.height
            )
            frames[state.id] = rect
            nodeFrames.append(NodeFrame(id: state.id, state: state, rect: rect))
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        nodes = nodeFrames
        framesByID = frames
        contentSize = CGSize(width: max(maxX, 1), height: max(maxY, 1))
        edges = diagram.transitions.enumerated().map { index, transition in
            EdgeLayout(id: index, from: transition.from, to: transition.to, label: transition.label)
        }
    }

    /// The laid-out frame for a state id, when the state exists.
    public func frame(for id: String) -> CGRect? {
        framesByID[id]
    }

    /// Estimated render size per state kind; normal/composite states grow with
    /// their title (mirroring `DiagramLayoutModel`'s text-based estimates).
    public static func estimatedSize(for state: StateDiagram.State) -> CGSize {
        switch state.kind {
        case .initial:
            return CGSize(width: 24, height: 24)
        case .final:
            return CGSize(width: 30, height: 30)
        case .choice:
            return CGSize(width: 44, height: 44)
        case .fork, .join:
            return CGSize(width: 80, height: 10)
        case .normal, .composite:
            let actionLines = [state.entryAction, state.exitAction, state.doActivity]
                .compactMap { $0 }.count
            let width = max(80, CGFloat(state.name.count) * 7.5 + 28)
            let height = 40 + CGFloat(actionLines) * 14
            return CGSize(width: width, height: height)
        }
    }
}
