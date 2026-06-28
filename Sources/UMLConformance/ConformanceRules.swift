import UMLCore

/// A declarative description of the intended architecture, validated against the relationship graph
/// to turn architectural intent into an executable contract. Decoded from a YAML rules file.
///
/// MVP rule kinds: forbidden dependencies, cycle detection, and metric budgets. Layering and
/// stereotype contracts are layered on in a later phase.
public struct ConformanceRules: Codable, Equatable, Sendable {
    /// "`from` must not depend on `to`" rules.
    public var forbidden: [DependencyRule]
    /// Optional cycle detection over modules (or types).
    public var cycles: CycleRule?
    /// Numeric guardrails on coupling/OO metrics.
    public var budgets: [MetricBudget]
    /// Optional ordered-layer rule: dependencies may only flow downward.
    public var layers: LayerRule?
    /// "Only `only`-matching types may depend into `into`" contracts.
    public var contracts: [StereotypeContract]

    public init(
        forbidden: [DependencyRule] = [],
        cycles: CycleRule? = nil,
        budgets: [MetricBudget] = [],
        layers: LayerRule? = nil,
        contracts: [StereotypeContract] = []
    ) {
        self.forbidden = forbidden
        self.cycles = cycles
        self.budgets = budgets
        self.layers = layers
        self.contracts = contracts
    }

    /// Lenient decoding so a rules file may omit any section it doesn't use (an absent `forbidden`/
    /// `budgets` is empty, not a decoding error).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forbidden = try container.decodeIfPresent([DependencyRule].self, forKey: .forbidden) ?? []
        cycles = try container.decodeIfPresent(CycleRule.self, forKey: .cycles)
        budgets = try container.decodeIfPresent([MetricBudget].self, forKey: .budgets) ?? []
        layers = try container.decodeIfPresent(LayerRule.self, forKey: .layers)
        contracts = try container.decodeIfPresent([StereotypeContract].self, forKey: .contracts) ?? []
    }

    /// The number of distinct rules evaluated — reported so a passing run still proves it checked
    /// something (an empty rules file is not silently "passing meaningfully").
    public var ruleCount: Int {
        forbidden.count + (cycles == nil ? 0 : 1) + budgets.count + (layers == nil ? 0 : 1) + contracts.count
    }
}

/// "`from` must not depend on `to`." A breach is any relationship whose source matches `from` and
/// target matches `to` (optionally restricted to certain edge `kinds`).
public struct DependencyRule: Codable, Equatable, Sendable {
    public var from: Selector
    public var to: Selector
    /// Which edge kinds count as a dependency for this rule; `nil` means all kinds.
    public var kinds: Set<Relationship.Kind>?
    /// Optional override for the violation message.
    public var message: String?

    public init(from: Selector, to: Selector, kinds: Set<Relationship.Kind>? = nil, message: String? = nil) {
        self.from = from
        self.to = to
        self.kinds = kinds
        self.message = message
    }
}

/// Flags dependency cycles as violations. MVP evaluates module-level cycles.
public struct CycleRule: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, Sendable, CaseIterable {
        case modules
        case types
    }

    public var scope: Scope

    public init(scope: Scope = .modules) {
        self.scope = scope
    }
}

/// A numeric guardrail: a metric on selector-matched modules/types must stay within `[min, max]`.
public struct MetricBudget: Codable, Equatable, Sendable {
    public enum Metric: String, Codable, Sendable, CaseIterable {
        // Per-module coupling metrics.
        case instability
        case abstractness
        case distance
        // Per-type OO metrics.
        case fanIn
        case fanOut
        case depthOfInheritance

        /// Module-scoped metrics are matched against module names; type-scoped against type nodes.
        public var isModuleScoped: Bool {
            switch self {
            case .instability, .abstractness, .distance:
                return true
            case .fanIn, .fanOut, .depthOfInheritance:
                return false
            }
        }
    }

    /// Which modules/types this budget applies to.
    public var target: Selector
    public var metric: Metric
    public var max: Double?
    public var min: Double?
    public var message: String?

    public init(
        target: Selector = Selector(),
        metric: Metric,
        max: Double? = nil,
        min: Double? = nil,
        message: String? = nil
    ) {
        self.target = target
        self.metric = metric
        self.max = max
        self.min = min
        self.message = message
    }

    /// Lenient decoding: `target` defaults to the whole-codebase selector when omitted, so a budget
    /// can read simply as `{ metric: distance, max: 0.5 }`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeIfPresent(Selector.self, forKey: .target) ?? Selector()
        metric = try container.decode(Metric.self, forKey: .metric)
        max = try container.decodeIfPresent(Double.self, forKey: .max)
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

/// An ordered set of architectural layers (top → bottom). Dependencies may only flow *downward*;
/// an edge from a lower layer up to a higher one is a violation. With `allowSkip == false` a layer
/// may depend only on the layer immediately beneath it. Types matching no layer are unconstrained.
public struct LayerRule: Codable, Equatable, Sendable {
    public struct Layer: Codable, Equatable, Sendable {
        public var name: String
        public var selector: Selector

        public init(name: String, selector: Selector) {
            self.name = name
            self.selector = selector
        }
    }

    /// Layers from top (index 0) to bottom; lower index = higher level.
    public var layers: [Layer]
    /// When `false`, a layer may depend only on the immediately adjacent lower layer.
    public var allowSkip: Bool

    public init(layers: [Layer], allowSkip: Bool = true) {
        self.layers = layers
        self.allowSkip = allowSkip
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layers = try container.decode([Layer].self, forKey: .layers)
        allowSkip = try container.decodeIfPresent(Bool.self, forKey: .allowSkip) ?? true
    }
}

/// "Only `only`-matching types may depend into `into`." Any edge whose target matches `into` but
/// whose source does *not* match `only` is a violation — e.g. only `@Repository` types may touch
/// the database layer.
public struct StereotypeContract: Codable, Equatable, Sendable {
    /// The protected region edges point *into*.
    public var into: Selector
    /// The only types allowed to depend into that region.
    public var only: Selector
    /// Which edge kinds count; `nil` means all kinds.
    public var kinds: Set<Relationship.Kind>?
    public var message: String?

    public init(into: Selector, only: Selector, kinds: Set<Relationship.Kind>? = nil, message: String? = nil) {
        self.into = into
        self.only = only
        self.kinds = kinds
        self.message = message
    }
}
