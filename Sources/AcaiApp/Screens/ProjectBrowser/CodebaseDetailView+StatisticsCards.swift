import SwiftUI
import AcaiCore

extension CodebaseDetailView {

    // MARK: - Statistics

    func statisticsSection(metrics: CodeMetrics) -> some View {
        CollapsibleSection(title: .app("View.CodebaseDetailView.Statistics")) {
            LazyVGrid(columns: cardColumns(count: 4), spacing: 12) {
                moduleMetricCards(metrics: metrics)
                classicMetricCards(metrics: metrics)
                smellMetricCards(metrics: metrics)
                structuralMetricCards(metrics: metrics)
            }
            .padding(.horizontal)
            .onPreferenceChange(CardHeightPreferenceKey.self) { height in
                if abs(statCardHeight - height) > 0.5 { statCardHeight = height }
            }
        }
    }

    @ViewBuilder
    private func moduleMetricCards(metrics: CodeMetrics) -> some View {
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Instability"), icon: "tornado",
                         family: .coupling, blurb: Self.instabilityBlurb),
            descriptor: .app("View.CodebaseDetailView.MostUnstable"), modules: metrics.modules,
            value: { $0.instability }, format: percent)
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Abstractness"),
                         icon: "cube.transparent", family: .coupling,
                         blurb: Self.abstractnessBlurb),
            descriptor: .app("View.CodebaseDetailView.MostAbstract"), modules: metrics.modules,
            value: { $0.abstractness }, format: percent)
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.DistanceMainSeq"), icon: "ruler", family: .coupling,
                         blurb: Self.distanceBlurb, threshold: MetricThreshold(amber: 0.3, red: 0.5)),
            descriptor: .app("View.CodebaseDetailView.Farthest"), modules: metrics.modules,
            value: { $0.distanceFromMainSequence }, format: percent)
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.SDPBreaches"),
                         icon: "arrow.down.forward.and.arrow.up.backward",
                         family: .coupling, blurb: Self.sdpBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            descriptor: .app("View.CodebaseDetailView.Most"), modules: metrics.modules,
            value: { Double($0.stableDependencyViolations.count) }, format: { Int($0).formatted() })
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.EfferentCe"),
                         icon: "arrow.up.right.square", family: .coupling,
                         blurb: Self.efferentBlurb),
            descriptor: .app("View.CodebaseDetailView.Most"), modules: metrics.modules,
            value: { Double($0.efferentCoupling) }, format: { Int($0).formatted() })
        moduleMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.AfferentCa"),
                         icon: "arrow.down.right.square", family: .coupling,
                         blurb: Self.afferentBlurb),
            descriptor: .app("View.CodebaseDetailView.MostDependedOn"), modules: metrics.modules,
            value: { Double($0.afferentCoupling) }, format: { Int($0).formatted() })
    }

    @ViewBuilder
    private func classicMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.InheritanceDepth"),
                         icon: "arrow.down.to.line", family: .oo,
                         blurb: Self.inheritanceDepthBlurb, threshold: MetricThreshold(amber: 4, red: 6)),
            by: \.depthOfInheritance, descriptor: .app("View.CodebaseDetailView.Deepest"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.FanOut"), icon: "arrow.up.right", family: .oo,
                         blurb: Self.fanOutBlurb,
                         threshold: MetricThreshold(amber: 10, red: 20)),
            by: \.fanOut, descriptor: .app("View.CodebaseDetailView.MostCoupled"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.FanIn"), icon: "arrow.down.left", family: .oo,
                         blurb: Self.fanInBlurb),
            by: \.fanIn, descriptor: .app("View.CodebaseDetailView.Hotspot"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Methods"), icon: "function", family: .oo,
                         blurb: Self.weightedMethodsBlurb, threshold: MetricThreshold(amber: 20, red: 40)),
            by: \.weightedMethods, descriptor: .app("View.CodebaseDetailView.Largest"), types: metrics.types)
    }

    @ViewBuilder
    private func smellMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.ResponseRFC"),
                         icon: "arrow.triangle.branch", family: .smell,
                         blurb: Self.responseForClassBlurb, threshold: MetricThreshold(amber: 30, red: 50)),
            by: \.responseForClass, descriptor: .app("View.CodebaseDetailView.Largest"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.PublicAPI"), icon: "lock.open", family: .smell,
                         blurb: Self.publicSurfaceBlurb, threshold: MetricThreshold(amber: 0.5, red: 0.75)),
            by: \.publicMemberRatio, descriptor: .app("View.CodebaseDetailView.Widest"), types: metrics.types,
            format: percent)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.MutablePublicState"),
                         icon: "pencil.and.outline", family: .smell,
                         blurb: Self.mutablePublicStateBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            by: \.mutablePublicState, descriptor: .app("View.CodebaseDetailView.Most"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Parameters"), icon: "slider.horizontal.3", family: .smell,
                         blurb: Self.parametersBlurb, threshold: MetricThreshold(amber: 4, red: 6)),
            by: \.maxParameters, descriptor: .app("View.CodebaseDetailView.Widest"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.DataClassScore"), icon: "tablecells", family: .smell,
                         blurb: Self.dataClassScoreBlurb, threshold: MetricThreshold(amber: 0.7, red: 0.9)),
            by: \.dataClassScore, descriptor: .app("View.CodebaseDetailView.MostData"), types: metrics.types,
            format: percent)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.NestingDepth"),
                         icon: "square.stack.3d.down.right", family: .smell,
                         blurb: Self.nestingDepthBlurb, threshold: MetricThreshold(amber: 3, red: 4)),
            by: \.nestingDepth, descriptor: .app("View.CodebaseDetailView.Deepest"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Overrides"), icon: "arrow.uturn.down", family: .smell,
                         blurb: Self.overrideCountBlurb, threshold: MetricThreshold(amber: 4, red: 8)),
            by: \.overrideCount, descriptor: .app("View.CodebaseDetailView.Most"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.DeepWide"),
                         icon: "arrow.up.and.down.and.arrow.left.and.right",
                         family: .smell, blurb: Self.deepAndWideBlurb,
                         threshold: MetricThreshold(amber: 6, red: 12)),
            by: \.deepAndWide, descriptor: .app("View.CodebaseDetailView.Hub"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.CohesionLCOM"), icon: "puzzlepiece", family: .smell,
                         blurb: Self.lackOfCohesionBlurb, threshold: MetricThreshold(amber: 2, red: 4)),
            by: \.lackOfCohesion, descriptor: .app("View.CodebaseDetailView.LeastCohesive"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.FeatureEnvy"), icon: "person.2", family: .smell,
                         blurb: Self.featureEnvyBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            by: \.featureEnvyMethods, descriptor: .app("View.CodebaseDetailView.Most"), types: metrics.types)
    }

    @ViewBuilder
    private func structuralMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.CyclomaticComplexity"),
                         icon: "arrow.triangle.branch", family: .structural,
                         blurb: Self.cyclomaticComplexityBlurb, threshold: MetricThreshold(amber: 10, red: 20)),
            by: \.maxCyclomaticComplexity,
            descriptor: .app("View.CodebaseDetailView.MostBranchy"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Properties"),
                         icon: "list.bullet.rectangle", family: .structural,
                         blurb: Self.numberOfPropertiesBlurb, threshold: MetricThreshold(amber: 15, red: 25)),
            by: \.numberOfProperties, descriptor: .app("View.CodebaseDetailView.Most"), types: metrics.types)
        typeMetricCard(
            MetricVisual(title: .app("View.CodebaseDetailView.Children"),
                         icon: "arrow.triangle.pull", family: .structural,
                         blurb: Self.numberOfChildrenBlurb),
            by: \.numberOfChildren, descriptor: .app("View.CodebaseDetailView.MostSubclassed"), types: metrics.types)
    }

    /// Bundled so the card builders stay within the parameter limit.
    struct MetricVisual {
        let title: LocalizedStringResource
        let icon: String
        let family: MetricFamily
        let blurb: LocalizedStringResource
        var threshold: MetricThreshold?
        var color: Color { family.color }
    }

    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>,
        descriptor: LocalizedStringResource, types: [CodeMetrics.TypeMetric]
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { Double($0[keyPath: keyPath]) }
        // Build the ranked drill-down lazily on tap — it sorts every type and resolves each row's
        // source file, so keeping it out of the render path matters when the pane re-lays out.
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: .app(
                "View.CodebaseDetailView.Max \(summary.maximum.formatted(.number.precision(.fractionLength(0))))"),
            secondary: .app(
                "View.CodebaseDetailView.Avg \(summary.average.formatted(.number.precision(.fractionLength(1))))"),
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = typeDetail(visual.title, visual.blurb, types, by: keyPath) }
                : nil)
    }

    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Double>,
        descriptor: LocalizedStringResource, types: [CodeMetrics.TypeMetric], format: @escaping (Double) -> String
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { $0[keyPath: keyPath] }
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: .app("View.CodebaseDetailView.Max \(format(summary.maximum))"),
            secondary: .app("View.CodebaseDetailView.Avg \(format(summary.average))"),
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = typeDetail(visual.title, visual.blurb, types, by: keyPath, format: format) }
                : nil)
    }

    private func moduleMetricCard(
        _ visual: MetricVisual, descriptor: LocalizedStringResource, modules: [CodeMetrics.ModuleCoupling],
        value: @escaping (CodeMetrics.ModuleCoupling) -> Double, format: @escaping (Double) -> String
    ) -> MetricStatCard {
        let summary = MetricSummary(modules, value: value)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: .app("View.CodebaseDetailView.Max \(format(summary.maximum))"),
            secondary: .app("View.CodebaseDetailView.Avg \(format(summary.average))"),
            exemplar: caption(descriptor, summary.exemplars.map(\.name)),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = moduleDetail(visual.title, visual.blurb, modules, value: value, format: format) }
                : nil)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "`descriptor`: name, name, name and N more" — or `nil` when there are no exemplars. Names
    /// beyond the first three are folded into a trailing count so a large tie stays one short line.
    private func caption(_ descriptor: LocalizedStringResource, _ names: [String]) -> LocalizedStringResource? {
        guard !names.isEmpty else { return nil }
        var shown = Array(names.prefix(3))
        let remaining = names.count - shown.count
        if remaining > 0 {
            shown.append(String(localized: .app("View.CodebaseDetailView.More \(remaining)")))
        }
        let list = shown.formatted(.list(type: .and))
        return .app("View.CodebaseDetailView.Exemplars \(String(localized: descriptor)) \(list)")
    }
}
