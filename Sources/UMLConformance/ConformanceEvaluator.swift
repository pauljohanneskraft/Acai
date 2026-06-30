import UMLCore

/// Validates a `CodeArtifact` against a `ConformanceRules` file and returns the violations — the
/// fitness-function core. Pure and language-agnostic: the `ModuleResolver` and annotation→stereotype
/// map are injected by the caller (resolved from the artifact's `LanguageConfiguration`).
public struct ConformanceEvaluator: Sendable {
    private let rules: ConformanceRules
    private let moduleResolver: ModuleResolver
    private let annotationStereotypes: [String: String]

    public init(
        rules: ConformanceRules,
        moduleResolver: ModuleResolver = .standard,
        annotationStereotypes: [String: String] = [:]
    ) {
        self.rules = rules
        self.moduleResolver = moduleResolver
        self.annotationStereotypes = annotationStereotypes
    }

    public func evaluate(_ artifact: CodeArtifact) -> ConformanceReport {
        let graph = GraphView(
            artifact: artifact,
            moduleResolver: moduleResolver,
            annotationStereotypes: annotationStereotypes
        )

        var violations: [Violation] = []
        violations += forbiddenViolations(graph)
        if let cycles = rules.cycles {
            violations += cycleViolations(graph, rule: cycles)
        }
        violations += budgetViolations(graph)
        if let layers = rules.layers {
            violations += layeringViolations(graph, rule: layers)
        }
        violations += contractViolations(graph)

        violations.sort {
            ($0.ruleKind, $0.subject, $0.source?.filePath ?? "", $0.source?.line ?? 0)
                < ($1.ruleKind, $1.subject, $1.source?.filePath ?? "", $1.source?.line ?? 0)
        }
        return ConformanceReport(violations: violations, checkedRuleCount: rules.ruleCount)
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

    private func budgetViolations(_ graph: GraphView) -> [Violation] {
        rules.budgets.flatMap { budget in
            budget.metric.isModuleScoped
                ? moduleBudgetViolations(graph, budget: budget)
                : typeBudgetViolations(graph, budget: budget)
        }
    }

    private func moduleBudgetViolations(_ graph: GraphView, budget: MetricBudget) -> [Violation] {
        graph.metrics.modules.compactMap { module in
            guard budget.target.matchesModule(named: module.name) else { return nil }
            let value: Double
            switch budget.metric {
            case .instability:
                value = module.instability
            case .abstractness:
                value = module.abstractness
            case .distance:
                value = module.distanceFromMainSequence
            default:
                return nil
            }
            return budget.breach(value: value, subject: module.name, source: nil)
        }
    }

    private func typeBudgetViolations(_ graph: GraphView, budget: MetricBudget) -> [Violation] {
        let nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return graph.metrics.types.compactMap { metric in
            guard let node = nodesByID[metric.id], budget.target.matches(node) else { return nil }
            let value: Double
            switch budget.metric {
            case .fanIn:
                value = Double(metric.fanIn)
            case .fanOut:
                value = Double(metric.fanOut)
            case .depthOfInheritance:
                value = Double(metric.depthOfInheritance)
            case .weightedMethods:
                value = Double(metric.weightedMethods)
            case .numberOfChildren:
                value = Double(metric.numberOfChildren)
            default:
                return nil
            }
            return budget.breach(value: value, subject: metric.id, source: node.location)
        }
    }
}

private extension MetricBudget {
    /// A violation when `value` falls outside `[min, max]`, else `nil`.
    func breach(value: Double, subject: String, source: SourceLocation?) -> Violation? {
        var problem: String?
        if let max, value > max { problem = "exceeds max \(format(max))" }
        if let min, value < min { problem = "below min \(format(min))" }
        guard let problem else { return nil }
        return Violation(
            ruleKind: "budget",
            message: message ?? "\(subject): \(metric.rawValue) \(format(value)) \(problem).",
            subject: subject,
            source: source,
            detail: ["metric": metric.rawValue, "value": format(value)]
        )
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
