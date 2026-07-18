import AcaiCore

/// A numeric guardrail: a metric on selector-matched modules/types must stay within `[min, max]`.
public struct MetricBudget: Codable, Equatable, Sendable {
    public enum Metric: String, Codable, Sendable, CaseIterable {
        // Per-module coupling metrics.
        case instability
        case abstractness
        case distance
        /// Public/open members across a module's types — its outward API surface.
        case publicApiSurface
        // Per-type OO metrics.
        case fanIn
        case fanOut
        case depthOfInheritance
        case weightedMethods
        case numberOfChildren
        case numberOfProperties
        /// Response For a Class: declared methods + distinct call targets — high = costly to test.
        case rfc
        /// Largest parameter count of any callable member — the long-parameter-list smell.
        case maxParameters
        /// Publicly settable stored properties — encapsulation leak.
        case mutablePublicState
        /// LCOM4 connected components among methods — high = unrelated responsibilities.
        case lcom
        /// Methods more interested in another declared type than their own — feature envy.
        case featureEnvyMethods
        /// Data-class / anemic score `properties / (properties + methods)` (1 = pure data).
        case dataClassScore
        /// Depth of the nested-type tree rooted at the type.
        case nestingDepth
        /// Highest cyclomatic complexity of any single method — the one gnarly method WMC hides.
        case maxCyclomaticComplexity

        /// Module-scoped metrics are matched against module names; type-scoped against type nodes.
        public var isModuleScoped: Bool {
            switch self {
            case .instability, .abstractness, .distance, .publicApiSurface:
                return true
            case .fanIn, .fanOut, .depthOfInheritance, .weightedMethods, .numberOfChildren,
                 .numberOfProperties, .rfc, .maxParameters, .mutablePublicState, .lcom,
                 .featureEnvyMethods, .dataClassScore, .nestingDepth, .maxCyclomaticComplexity:
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

    /// The built-in code-smell budgets: sensible starting thresholds for the type-scoped smell
    /// metrics, applied whenever a project runs the quality check without its own `quality.yml`. Each
    /// is a whole-codebase budget, so a project graduates the ones it cares about into its config
    /// unchanged.
    /// `mutablePublicState` is deliberately *not* here: publicly-settable stored properties are
    /// idiomatic in value types, so it floods struct-heavy code as a default. Gate it explicitly via a
    /// `quality.yml` when a project wants it.
    public static let defaultSmellBudgets: [MetricBudget] = [
        MetricBudget(metric: .maxParameters, max: 5, message: nil),
        MetricBudget(metric: .dataClassScore, max: 0.8, message: nil),
        MetricBudget(metric: .nestingDepth, max: 2, message: nil),
        MetricBudget(metric: .lcom, max: 1, message: nil),
        MetricBudget(metric: .featureEnvyMethods, max: 2, message: nil),
        MetricBudget(metric: .maxCyclomaticComplexity, max: 10, message: nil)
    ]

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

extension MetricBudget.Metric {
    /// This metric's value on a per-type metric row, or `nil` when the metric is module-scoped. A
    /// lookup table rather than a large `switch` keeps the accessor within the complexity budget.
    func value(in type: CodeMetrics.TypeMetric) -> Double? {
        Self.typeAccessors[self]?(type)
    }

    /// This metric's value on a per-module coupling row, or `nil` when the metric is type-scoped.
    func value(in module: CodeMetrics.ModuleCoupling) -> Double? {
        Self.moduleAccessors[self]?(module)
    }

    private static let typeAccessors: [MetricBudget.Metric: @Sendable (CodeMetrics.TypeMetric) -> Double] = [
        .fanIn: { Double($0.fanIn) },
        .fanOut: { Double($0.fanOut) },
        .depthOfInheritance: { Double($0.depthOfInheritance) },
        .weightedMethods: { Double($0.weightedMethods) },
        .numberOfChildren: { Double($0.numberOfChildren) },
        .numberOfProperties: { Double($0.numberOfProperties) },
        .rfc: { Double($0.responseForClass) },
        .maxParameters: { Double($0.maxParameters) },
        .mutablePublicState: { Double($0.mutablePublicState) },
        .lcom: { Double($0.lackOfCohesion) },
        .featureEnvyMethods: { Double($0.featureEnvyMethods) },
        .dataClassScore: { $0.dataClassScore },
        .nestingDepth: { Double($0.nestingDepth) },
        .maxCyclomaticComplexity: { Double($0.maxCyclomaticComplexity) }
    ]

    private static let moduleAccessors: [MetricBudget.Metric: @Sendable (CodeMetrics.ModuleCoupling) -> Double] = [
        .instability: { $0.instability },
        .abstractness: { $0.abstractness },
        .distance: { $0.distanceFromMainSequence },
        .publicApiSurface: { Double($0.publicMemberCount) }
    ]

    /// A one-line remediation hint for this metric when it reads as a smell — appended to a budget
    /// breach so the report says how to fix it, not just that a ceiling was crossed.
    var smellHint: String {
        switch self {
        case .maxParameters:
            return "introduce a parameter object"
        case .mutablePublicState:
            return "make the setter private and expose intent-revealing methods"
        case .dataClassScore:
            return "move behaviour onto this type instead of reaching into it"
        case .nestingDepth:
            return "flatten or extract the nested types"
        case .lcom:
            return "split the type — its methods form unrelated clusters"
        case .featureEnvyMethods:
            return "move the envious methods to the type they use most"
        case .rfc:
            return "reduce the type's call surface to make it cheaper to test"
        case .weightedMethods:
            return "extract collaborators — the type does too much"
        case .numberOfProperties:
            return "group related fields into a value type"
        case .maxCyclomaticComplexity:
            return "extract the branchy method — split its decision paths"
        case .fanIn, .fanOut, .depthOfInheritance, .numberOfChildren,
             .instability, .abstractness, .distance, .publicApiSurface:
            return "review this coupling metric"
        }
    }
}
