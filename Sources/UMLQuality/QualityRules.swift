import UMLCore

/// A declarative description of the intended architecture and code quality, validated against the
/// relationship graph and metrics to turn design intent into an executable contract. Decoded from a
/// YAML rules file (`quality.yml`).
///
/// Rule kinds: forbidden dependencies, dependency cycles, metric budgets (which subsume the code
/// smells), ordered layers, and stereotype contracts.
public struct QualityRules: Codable, Equatable, Sendable {
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

    /// The rules applied when a project runs the quality check without its own `quality.yml`: the
    /// curated code-smell budgets. So a no-config `uml quality` still flags god classes, feature envy,
    /// long parameter lists, low cohesion, and the like out of the box.
    public static let defaultQuality = QualityRules(budgets: MetricBudget.defaultSmellBudgets)
}
