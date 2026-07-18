import CoreGraphics
import Foundation
import AcaiCore
import AcaiDiagram

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
        // `LayerAssignment` puts inheritance *targets* in the top layer, so feed each transition
        // reversed (origin state as the "parent"), placing the initial pseudo-state at the top and
        // flowing downward.
        let layout = DirectedGraphLayout(
            nodeSizes: diagram.states.map { ($0.id, Self.estimatedSize(for: $0)) },
            edges: diagram.transitions.map { ($0.to, $0.from) },
            positionOverrides: positionOverrides
        )
        framesByID = layout.framesByID
        contentSize = layout.contentSize
        nodes = diagram.states.map { NodeFrame(id: $0.id, state: $0, rect: layout.framesByID[$0.id] ?? .zero) }
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
