import AcaiCore

/// An expected change in a metric's value since a `--baseline`, checked by comparing two analyses of
/// the same codebase. `minImprovement` is the minimum required decrease: `0` (the default) means "must
/// not get worse"; a positive value additionally requires an improvement of at least that much.
///
/// Declaring a movement also guards its target against a *hidden* regression: every other metric of
/// the same scope (module- or type-level) on that target must not have gotten worse either, so an
/// improvement bought by a cost elsewhere doesn't pass silently.
public struct MetricMovement: Codable, Equatable, Sendable {
    public var target: Selector
    public var metric: MetricBudget.Metric
    public var minImprovement: Double
    public var message: String?

    public init(
        target: Selector = Selector(),
        metric: MetricBudget.Metric,
        minImprovement: Double = 0,
        message: String? = nil
    ) {
        self.target = target
        self.metric = metric
        self.minImprovement = minImprovement
        self.message = message
    }

    /// Lenient decoding: `target` defaults to the whole-codebase selector and `minImprovement` to `0`
    /// ("must not regress"), so a movement can read simply as `{ metric: fanOut }`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeIfPresent(Selector.self, forKey: .target) ?? Selector()
        metric = try container.decode(MetricBudget.Metric.self, forKey: .metric)
        minImprovement = try container.decodeIfPresent(Double.self, forKey: .minImprovement) ?? 0
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

extension MetricMovement {
    /// `nil` when `after` improved on `before` by at least `minImprovement`; otherwise a violation
    /// describing the shortfall — including an outright regression when the value got worse.
    func violation(before: Double, after: Double, subject: String, source: SourceLocation?) -> Violation? {
        let improvement = before - after
        guard improvement < minImprovement else { return nil }
        let fallback = minImprovement > 0
            ? "\(subject): \(metric.rawValue) moved from \(format(before)) to \(format(after))"
                + " — required a decrease of at least \(format(minImprovement))."
            : "\(subject): \(metric.rawValue) regressed from \(format(before)) to \(format(after))."
        return Violation(
            ruleKind: "movement",
            message: message ?? fallback,
            subject: subject,
            source: source,
            detail: ["metric": metric.rawValue, "before": format(before), "after": format(after)]
        )
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

extension MetricBudget.Metric {
    /// `false` for `instability` and `abstractness`: they are the two additive components of
    /// `distance` (`|abstractness + instability - 1|`), so improving `distance` — the metric with an
    /// actual "closer to 0 is better" direction — mechanically moves at least one of them. Flagging
    /// that move as a *hidden* regression would misfire on the very mechanism the improvement used.
    /// An author who wants either gated declares an explicit `MetricMovement` (or `MetricBudget`) for
    /// it instead of relying on the automatic guard. Used only by `QualityEvaluator`'s
    /// hidden-regression scan — an explicitly declared movement is never restricted by this.
    var isEligibleForHiddenRegressionScan: Bool {
        switch self {
        case .instability, .abstractness:
            return false
        case .distance, .publicApiSurface, .fanIn, .fanOut, .depthOfInheritance, .weightedMethods,
             .numberOfChildren, .numberOfProperties, .rfc, .maxParameters, .mutablePublicState, .lcom,
             .featureEnvyMethods, .dataClassScore, .nestingDepth, .maxCyclomaticComplexity:
            return true
        }
    }
}
