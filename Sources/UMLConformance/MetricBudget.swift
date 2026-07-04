import UMLCore

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

        /// Module-scoped metrics are matched against module names; type-scoped against type nodes.
        public var isModuleScoped: Bool {
            switch self {
            case .instability, .abstractness, .distance, .publicApiSurface:
                return true
            case .fanIn, .fanOut, .depthOfInheritance, .weightedMethods, .numberOfChildren,
                 .numberOfProperties, .rfc, .maxParameters, .mutablePublicState, .lcom,
                 .featureEnvyMethods, .dataClassScore, .nestingDepth:
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
        .nestingDepth: { Double($0.nestingDepth) }
    ]

    private static let moduleAccessors: [MetricBudget.Metric: @Sendable (CodeMetrics.ModuleCoupling) -> Double] = [
        .instability: { $0.instability },
        .abstractness: { $0.abstractness },
        .distance: { $0.distanceFromMainSequence },
        .publicApiSurface: { Double($0.publicMemberCount) }
    ]
}
