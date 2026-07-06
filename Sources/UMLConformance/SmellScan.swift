import UMLCore

/// Runs the code-smell metrics against a set of thresholds and reports each breach as a ranked
/// `Violation` (worst first), each carrying `file:line` and a fix hint. The thresholds are the same
/// `MetricBudget` values `check` gates on, so a project can start from these curated defaults and
/// graduate the ones it cares about into its `architecture.yml` unchanged.
///
/// A value you instantiate over an artifact (`SmellScan(artifact:).findings`). Agnostic — it reads
/// per-type metrics and resolves selector facets against the injected `LanguageConfiguration` map.
public struct SmellScan: Sendable {
    /// The built-in thresholds: sensible starting points for the type-scoped smell metrics. Each is a
    /// whole-codebase `MetricBudget`, so callers can pass their own (e.g. loaded from a rules file) to
    /// override or extend the set.
    /// `mutablePublicState` is deliberately *not* here: publicly-settable stored properties are
    /// idiomatic in value types, so it floods struct-heavy code as a default. Gate it explicitly via a
    /// rules file / `check` when a project wants it.
    public static let defaultThresholds: [MetricBudget] = [
        MetricBudget(metric: .maxParameters, max: 5, message: nil),
        MetricBudget(metric: .dataClassScore, max: 0.8, message: nil),
        MetricBudget(metric: .nestingDepth, max: 2, message: nil),
        MetricBudget(metric: .lcom, max: 1, message: nil),
        MetricBudget(metric: .featureEnvyMethods, max: 2, message: nil)
    ]

    private let artifact: CodeArtifact
    private let thresholds: [MetricBudget]
    private let selector: Selector
    private let moduleResolver: ModuleResolver
    private let languageResolver: LanguageConfigurationResolver

    public init(
        artifact: CodeArtifact,
        thresholds: [MetricBudget] = SmellScan.defaultThresholds,
        selector: Selector = Selector(),
        moduleResolver: ModuleResolver = .standard,
        languageResolver: LanguageConfigurationResolver
    ) {
        self.artifact = artifact
        self.thresholds = thresholds
        self.selector = selector
        self.moduleResolver = moduleResolver
        self.languageResolver = languageResolver
    }

    /// Every threshold breach across the codebase's types, ranked most-severe first (by how far the
    /// value overshoots its threshold, relative to the threshold).
    public var findings: [Violation] {
        let graph = GraphView(
            artifact: artifact,
            moduleResolver: moduleResolver,
            languageResolver: languageResolver)
        let nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let scored = graph.metrics.types.flatMap { metric -> [(severity: Double, violation: Violation)] in
            guard let node = nodesByID[metric.id], selector.matches(node) else { return [] }
            return thresholds.compactMap { budget in
                guard budget.target.matches(node),
                      let value = budget.metric.value(in: metric),
                      let max = budget.max, value > max else { return nil }
                let severity = max == 0 ? value : (value - max) / max
                return (severity, smell(metric: budget.metric, value: value, max: max, node: node))
            }
        }

        let typesByID = Dictionary(
            artifact.flattened().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rank(scored).map { violation in
            enrichWithCohesionPartition(violation, typesByID: typesByID)
        }
    }

    /// Ranks scored violations most-severe first (ties broken by subject for stable output).
    private func rank(
        _ scored: [(severity: Double, violation: Violation)]
    ) -> [Violation] {
        scored
            .sorted { ($0.severity, $0.violation.subject) > ($1.severity, $1.violation.subject) }
            .map(\.violation)
    }

    /// For a low-cohesion (`lcom`) finding, appends the actual method clusters so the report says *how*
    /// to split the type, not just that it should be split. A no-op for every other smell.
    private func enrichWithCohesionPartition(
        _ violation: Violation, typesByID: [String: TypeDeclaration]
    ) -> Violation {
        guard violation.detail["metric"] == MetricBudget.Metric.lcom.rawValue,
              let type = typesByID[violation.subject] else { return violation }
        let clusters = LcomAnalysis(type: type).components
            .map { "{" + $0.joined(separator: ", ") + "}" }
            .joined(separator: " | ")
        var enriched = violation
        enriched.detail["clusters"] = clusters
        enriched.message += " — clusters: \(clusters)"
        return enriched
    }

    private func smell(
        metric: MetricBudget.Metric, value: Double, max: Double, node: GraphView.Node
    ) -> Violation {
        Violation(
            ruleKind: "smell",
            message: "\(node.id): \(metric.rawValue) \(format(value)) exceeds \(format(max)) — \(metric.smellHint)",
            subject: node.id,
            source: node.location,
            detail: [
                "metric": metric.rawValue,
                "value": format(value),
                "threshold": format(max)
            ])
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

extension MetricBudget.Metric {
    /// A one-line remediation hint for this metric when it reads as a smell.
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
        case .fanIn, .fanOut, .depthOfInheritance, .numberOfChildren,
             .instability, .abstractness, .distance, .publicApiSurface:
            return "review this coupling metric"
        }
    }
}
