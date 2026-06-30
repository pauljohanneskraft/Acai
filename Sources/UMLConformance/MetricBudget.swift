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
        case weightedMethods
        case numberOfChildren

        /// Module-scoped metrics are matched against module names; type-scoped against type nodes.
        public var isModuleScoped: Bool {
            switch self {
            case .instability, .abstractness, .distance:
                return true
            case .fanIn, .fanOut, .depthOfInheritance, .weightedMethods, .numberOfChildren:
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
