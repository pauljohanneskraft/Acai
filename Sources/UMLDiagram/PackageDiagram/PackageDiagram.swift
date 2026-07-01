import Foundation

/// A package/module **dependency diagram**: one node per build module (SwiftPM
/// target, Gradle/Maven module, JS package — see `ModuleResolver`), with a weighted
/// edge for every cross-module reference. Each node carries Robert Martin's
/// package metrics so the diagram doubles as a coupling/stability overview.
public struct PackageDiagram: Codable, Hashable, Sendable {

    // MARK: - Node

    /// One build module, annotated with its coupling metrics.
    public struct Node: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
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
            typeCount: Int,
            afferentCoupling: Int,
            efferentCoupling: Int,
            instability: Double,
            abstractness: Double
        ) {
            self.id = id
            self.name = name
            self.typeCount = typeCount
            self.afferentCoupling = afferentCoupling
            self.efferentCoupling = efferentCoupling
            self.instability = instability
            self.abstractness = abstractness
        }
    }

    // MARK: - Edge

    /// A directed dependency from one module to another.
    public struct Edge: Codable, Hashable, Sendable {
        public var from: String  // node id
        public var to: String    // node id
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
}
