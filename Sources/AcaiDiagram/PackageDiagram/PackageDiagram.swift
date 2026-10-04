import AcaiCore
import Foundation

/// A package/module **dependency diagram**: one node per build module (SwiftPM
/// target, Gradle/Maven module, JS package — see `ModuleResolver`), with a weighted
/// edge for every cross-module reference. Each node carries Robert Martin's
/// package metrics so the diagram doubles as a coupling/stability overview.
public struct PackageDiagram: Codable, Hashable, Sendable {

    // MARK: - Node

    public struct Node: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// The project this module belongs to, when the analysed folder held more than one — the
        /// outer box the module is drawn inside. `nil` for a single-project folder, where every
        /// module shares the one project and an outer box says nothing.
        public var project: String?
        public var typeCount: Int
        /// Afferent coupling (Ca): external types that depend on this module.
        public var afferentCoupling: Int
        /// Efferent coupling (Ce): external types this module depends on.
        public var efferentCoupling: Int
        /// Instability `I = Ce / (Ca + Ce)` (0 = stable, 1 = unstable).
        public var instability: Double
        /// Abstractness `A = abstractTypes / totalTypes`.
        public var abstractness: Double

        /// Distance from the main sequence `D = |A + I − 1|` (0 = balanced,
        /// 1 = either the "zone of pain" or the "zone of uselessness").
        public var distanceFromMainSequence: Double {
            abs(abstractness + instability - 1)
        }

        public var mainSequenceZone: MainSequenceZone {
            MainSequenceZone(instability: instability, distanceFromMainSequence: distanceFromMainSequence)
        }

        /// A green→red hex tint (`#rrggbb`) keyed on `distanceFromMainSequence`, shared by the
        /// DOT, Mermaid, and in-app renderers so a module is shaded identically everywhere.
        public var zoneColorHex: String {
            switch distanceFromMainSequence {
            case ..<0.25:
                return "#c8e6c9"  // balanced
            case ..<0.5:
                return "#fff9c4"  // drifting
            case ..<0.75:
                return "#ffe0b2"  // concerning
            default:
                return "#ffcdd2"  // zone of pain / uselessness
            }
        }

        public init(
            id: String,
            name: String,
            project: String? = nil,
            typeCount: Int,
            afferentCoupling: Int,
            efferentCoupling: Int,
            instability: Double,
            abstractness: Double
        ) {
            self.id = id
            self.name = name
            self.project = project
            self.typeCount = typeCount
            self.afferentCoupling = afferentCoupling
            self.efferentCoupling = efferentCoupling
            self.instability = instability
            self.abstractness = abstractness
        }
    }

    // MARK: - Edge

    public struct Edge: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
        /// Number of distinct cross-module type references along this edge.
        public var weight: Int

        public init(from: String, to: String, weight: Int = 1) {
            self.from = from
            self.to = to
            self.weight = weight
        }
    }

    // MARK: - Diagram

    public var title: String?
    public var nodes: [Node]
    public var edges: [Edge]

    public init(title: String? = nil, nodes: [Node] = [], edges: [Edge] = []) {
        self.title = title
        self.nodes = nodes
        self.edges = edges
    }

    /// Stable-Dependencies-Principle breaches: edges pointing at a *less* stable module (strictly
    /// higher instability). Read off the diagram's own nodes, using the same comparison
    /// `CodeMetrics.ModuleCoupling.stableDependencyViolations` makes, so no second metrics pass is
    /// needed to mark them.
    public var stableDependencyBreaches: Set<Edge> {
        let instabilityByID = Dictionary(nodes.map { ($0.id, $0.instability) }) { first, _ in first }
        return Set(edges.filter { edge in
            guard let from = instabilityByID[edge.from], let to = instabilityByID[edge.to] else { return false }
            return to > from
        })
    }
}
