import AcaiCore

/// Validates a `CodeArtifact` against a `QualityRules` file and returns the violations — the
/// fitness-function core. Pure and language-agnostic: the `ModuleResolver` and annotation→stereotype
/// map are injected by the caller (resolved from the artifact's `LanguageConfiguration`).
public struct QualityEvaluator: Sendable {
    private let rules: QualityRules
    private let moduleResolver: ModuleResolver
    private let languageResolver: LanguageConfigurationResolver

    public init(
        rules: QualityRules,
        moduleResolver: ModuleResolver = .standard,
        languageResolver: LanguageConfigurationResolver
    ) {
        self.rules = rules
        self.moduleResolver = moduleResolver
        self.languageResolver = languageResolver
    }

    public func evaluate(_ rawArtifact: CodeArtifact) -> QualityReport {
        // Machine-generated types are dropped before evaluation unless the rules opt in — so budgets
        // and cycles reflect only hand-written code. Idempotent, so a pre-filtered artifact is fine.
        let artifact = rules.includeGeneratedTypes
            ? rawArtifact
            : rawArtifact.filteringGeneratedTypes(using: languageResolver)
        let graph = GraphView(
            artifact: artifact,
            moduleResolver: moduleResolver,
            languageResolver: languageResolver
        )

        let typesByID = Dictionary(
            artifact.flattened().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The structural rule findings (forbidden deps, cycles, layering, contracts) in a stable,
        // deterministic order — CI diffs shouldn't churn on reordering.
        var structural: [Violation] = []
        structural += forbiddenViolations(graph)
        if let cycles = rules.cycles {
            structural += cycleViolations(graph, rule: cycles)
        }
        if let layers = rules.layers {
            structural += layeringViolations(graph, rule: layers)
        }
        structural += contractViolations(graph)
        structural.sort {
            ($0.ruleKind, $0.subject, $0.source?.filePath ?? "", $0.source?.line ?? 0)
                < ($1.ruleKind, $1.subject, $1.source?.filePath ?? "", $1.source?.line ?? 0)
        }

        // Budget findings (the merged code smells) lead, ranked worst-first, so the report opens with
        // the highest-leverage refactors; the structural findings follow in deterministic order.
        let budgets = budgetViolations(graph, typesByID: typesByID)
        return QualityReport(violations: budgets + structural, checkedRuleCount: rules.ruleCount)
    }

    // MARK: - Forbidden dependencies

    private func forbiddenViolations(_ graph: GraphView) -> [Violation] {
        var violations: [Violation] = []
        for rule in rules.forbidden {
            for edge in graph.relationships {
                if let kinds = rule.kinds, !kinds.contains(edge.kind) { continue }
                guard let source = graph.node(id: edge.source),
                      let target = graph.node(id: edge.target),
                      rule.from.matches(source), rule.to.matches(target)
                else { continue }
                let fallback = "Forbidden dependency: \(source.id) → \(target.id) (\(edge.kind.rawValue))."
                violations.append(Violation(
                    ruleKind: "forbidden-dependency",
                    message: rule.message ?? fallback,
                    subject: "\(source.id)→\(target.id)",
                    source: source.location,
                    detail: ["kind": edge.kind.rawValue, "from": source.module, "to": target.module]
                ))
            }
        }
        return violations
    }

    // MARK: - Cycles

    private func cycleViolations(_ graph: GraphView, rule: CycleRule) -> [Violation] {
        let finder = CycleFinder(graph: graph, moduleResolver: moduleResolver)
        let scope: CycleFinder.Scope = rule.scope == .modules ? .modules : .types
        let label = scope == .modules ? "Module" : "Type"
        return finder.cycles(scope: scope).map { cycle in
            Violation(
                ruleKind: "cycle",
                message: "\(label) dependency cycle: \(cycle.description).",
                subject: cycle.members.joined(separator: ","),
                // Type cycles can point at the first member's declaration; module cycles have no single site.
                source: scope == .types ? graph.node(id: cycle.members[0])?.location : nil,
                detail: ["scope": scope.rawValue]
            )
        }
    }

    // MARK: - Layering

    private func layeringViolations(_ graph: GraphView, rule: LayerRule) -> [Violation] {
        // Assign each type the index of the first layer whose selector matches it.
        var layerOf: [String: Int] = [:]
        for node in graph.nodes {
            if let index = rule.layers.firstIndex(where: { $0.selector.matches(node) }) {
                layerOf[node.id] = index
            }
        }

        var violations: [Violation] = []
        for edge in graph.relationships {
            guard let source = graph.node(id: edge.source),
                  let from = layerOf[edge.source], let to = layerOf[edge.target],
                  from != to else { continue }
            // Higher index = lower layer. Downward (from < to) is allowed; upward is a violation,
            // and a skip beyond the adjacent layer is too when `allowSkip` is off.
            let isUpward = to < from
            let isIllegalSkip = !rule.allowSkip && to > from + 1
            guard isUpward || isIllegalSkip else { continue }
            let direction = isUpward ? "upward" : "skipping"
            violations.append(Violation(
                ruleKind: "layering",
                message: "Illegal \(direction) dependency: \(rule.layers[from].name) → \(rule.layers[to].name)"
                    + " (\(source.id) → \(edge.target)).",
                subject: "\(source.id)→\(edge.target)",
                source: source.location,
                detail: ["from": rule.layers[from].name, "to": rule.layers[to].name]
            ))
        }
        return violations
    }

    // MARK: - Stereotype contracts

    private func contractViolations(_ graph: GraphView) -> [Violation] {
        var violations: [Violation] = []
        for contract in rules.contracts {
            for edge in graph.relationships {
                if let kinds = contract.kinds, !kinds.contains(edge.kind) { continue }
                guard let source = graph.node(id: edge.source), let target = graph.node(id: edge.target),
                      contract.into.matches(target), !contract.only.matches(source)
                else { continue }
                let fallback = "Contract breach: \(source.id) → \(target.id) is not permitted to depend here."
                violations.append(Violation(
                    ruleKind: "contract",
                    message: contract.message ?? fallback,
                    subject: "\(source.id)→\(target.id)",
                    source: source.location,
                    detail: ["kind": edge.kind.rawValue]
                ))
            }
        }
        return violations
    }

    // MARK: - Budgets

    /// Budget breaches (the merged code smells), ranked **worst-first** by how far each value
    /// overshoots its bound relative to the bound — so the report leads with the highest-leverage
    /// refactors. Ties break by subject for stable output.
    private func budgetViolations(_ graph: GraphView, typesByID: [String: TypeDeclaration]) -> [Violation] {
        let scored = rules.budgets.flatMap { budget in
            budget.metric.isModuleScoped
                ? moduleBudgetViolations(graph, budget: budget)
                : typeBudgetViolations(graph, budget: budget, typesByID: typesByID)
        }
        return scored
            .sorted { ($0.severity, $0.violation.subject) > ($1.severity, $1.violation.subject) }
            .map(\.violation)
    }

    private func moduleBudgetViolations(
        _ graph: GraphView, budget: MetricBudget
    ) -> [(severity: Double, violation: Violation)] {
        graph.metrics.modules.compactMap { module in
            guard budget.target.matchesModule(named: module.name),
                  let value = budget.metric.value(in: module) else { return nil }
            return budget.breach(value: value, subject: module.name, source: nil)
        }
    }

    private func typeBudgetViolations(
        _ graph: GraphView, budget: MetricBudget, typesByID: [String: TypeDeclaration]
    ) -> [(severity: Double, violation: Violation)] {
        let nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return graph.metrics.types.compactMap { metric in
            guard let node = nodesByID[metric.id], budget.target.matches(node),
                  let value = budget.metric.value(in: metric) else { return nil }
            guard let (severity, violation) = budget.breach(
                value: value, subject: metric.id, source: node.location) else { return nil }
            return (severity, enrichWithCohesionPartition(violation, budget: budget, typesByID: typesByID))
        }
    }

    /// For a low-cohesion (`lcom`) budget breach, appends the actual method clusters so the report
    /// says *how* to split the type, not just that it should be. A no-op for every other metric.
    private func enrichWithCohesionPartition(
        _ violation: Violation, budget: MetricBudget, typesByID: [String: TypeDeclaration]
    ) -> Violation {
        guard budget.metric == .lcom, let type = typesByID[violation.subject] else { return violation }
        let clusters = LcomAnalysis(type: type).components
            .map { "{" + $0.joined(separator: ", ") + "}" }
            .joined(separator: " | ")
        var enriched = violation
        enriched.detail["clusters"] = clusters
        enriched.message += " — clusters: \(clusters)"
        return enriched
    }
}

private extension MetricBudget {
    /// A breach when `value` falls outside `[min, max]`, else `nil`, paired with its *severity* — how
    /// far the value overshoots its bound relative to the bound — so the findings can be ranked
    /// worst-first. The message carries the metric's `smellHint` so a breach reads as actionable
    /// remediation, not just a crossed ceiling.
    func breach(value: Double, subject: String, source: SourceLocation?) -> (severity: Double, violation: Violation)? {
        var problem: String?
        var severity = 0.0
        if let max, value > max {
            problem = "exceeds max \(format(max))"
            severity = max == 0 ? value : (value - max) / max
        }
        if let min, value < min {
            problem = "below min \(format(min))"
            severity = min == 0 ? value : (min - value) / min
        }
        guard let problem else { return nil }
        let fallback = "\(subject): \(metric.rawValue) \(format(value)) \(problem) — \(metric.smellHint)."
        let violation = Violation(
            ruleKind: "budget",
            message: message ?? fallback,
            subject: subject,
            source: source,
            detail: ["metric": metric.rawValue, "value": format(value)]
        )
        return (severity, violation)
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
