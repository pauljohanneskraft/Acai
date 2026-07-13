import SwiftUI
import UMLCore

// The statistics section and its stat-card builders. Kept in a separate file (same module) so
// `CodebaseDetailView.swift` stays within SwiftLint's `file_length`.
extension CodebaseDetailView {

    // MARK: - Statistics

    func statisticsSection(metrics: CodeMetrics) -> some View {
        CollapsibleSection(title: "Statistics") {
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

    /// Per-module Robert Martin coupling metrics (Ca/Ce, instability, abstractness, distance, SDP).
    @ViewBuilder
    private func moduleMetricCards(metrics: CodeMetrics) -> some View {
        moduleMetricCard(
            MetricVisual(title: "Instability", icon: "tornado", family: .coupling, blurb: Self.instabilityBlurb),
            descriptor: "Most unstable", modules: metrics.modules, value: { $0.instability }, format: percent)
        moduleMetricCard(
            MetricVisual(title: "Abstractness", icon: "cube.transparent", family: .coupling,
                         blurb: Self.abstractnessBlurb),
            descriptor: "Most abstract", modules: metrics.modules, value: { $0.abstractness }, format: percent)
        moduleMetricCard(
            MetricVisual(title: "Distance (Main Seq.)", icon: "ruler", family: .coupling,
                         blurb: Self.distanceBlurb, threshold: MetricThreshold(amber: 0.3, red: 0.5)),
            descriptor: "Farthest", modules: metrics.modules,
            value: { $0.distanceFromMainSequence }, format: percent)
        moduleMetricCard(
            MetricVisual(title: "SDP Breaches", icon: "arrow.down.forward.and.arrow.up.backward",
                         family: .coupling, blurb: Self.sdpBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            descriptor: "Most", modules: metrics.modules,
            value: { Double($0.stableDependencyViolations.count) }, format: { String(Int($0)) })
        moduleMetricCard(
            MetricVisual(title: "Efferent (Ce)", icon: "arrow.up.right.square", family: .coupling,
                         blurb: Self.efferentBlurb),
            descriptor: "Most", modules: metrics.modules,
            value: { Double($0.efferentCoupling) }, format: { String(Int($0)) })
        moduleMetricCard(
            MetricVisual(title: "Afferent (Ca)", icon: "arrow.down.right.square", family: .coupling,
                         blurb: Self.afferentBlurb),
            descriptor: "Most depended-on", modules: metrics.modules,
            value: { Double($0.afferentCoupling) }, format: { String(Int($0)) })
    }

    /// The classic per-type OO metrics (DIT/fan/WMC).
    @ViewBuilder
    private func classicMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: "Inheritance Depth", icon: "arrow.down.to.line", family: .oo,
                         blurb: Self.inheritanceDepthBlurb, threshold: MetricThreshold(amber: 4, red: 6)),
            by: \.depthOfInheritance, descriptor: "Deepest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Fan-out", icon: "arrow.up.right", family: .oo, blurb: Self.fanOutBlurb,
                         threshold: MetricThreshold(amber: 10, red: 20)),
            by: \.fanOut, descriptor: "Most coupled", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Fan-in", icon: "arrow.down.left", family: .oo, blurb: Self.fanInBlurb),
            by: \.fanIn, descriptor: "Hotspot", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Methods", icon: "function", family: .oo,
                         blurb: Self.weightedMethodsBlurb, threshold: MetricThreshold(amber: 20, red: 40)),
            by: \.weightedMethods, descriptor: "Largest", types: metrics.types)
    }

    /// The code-smell folds (issue #101).
    @ViewBuilder
    private func smellMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: "Response (RFC)", icon: "arrow.triangle.branch", family: .smell,
                         blurb: Self.responseForClassBlurb, threshold: MetricThreshold(amber: 30, red: 50)),
            by: \.responseForClass, descriptor: "Largest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Public API", icon: "lock.open", family: .smell,
                         blurb: Self.publicSurfaceBlurb, threshold: MetricThreshold(amber: 0.5, red: 0.75)),
            by: \.publicMemberRatio, descriptor: "Widest", types: metrics.types,
            format: { String(format: "%.0f%%", $0 * 100) })
        typeMetricCard(
            MetricVisual(title: "Mutable Public State", icon: "pencil.and.outline", family: .smell,
                         blurb: Self.mutablePublicStateBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            by: \.mutablePublicState, descriptor: "Most", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Parameters", icon: "slider.horizontal.3", family: .smell,
                         blurb: Self.parametersBlurb, threshold: MetricThreshold(amber: 4, red: 6)),
            by: \.maxParameters, descriptor: "Widest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Data-class Score", icon: "tablecells", family: .smell,
                         blurb: Self.dataClassScoreBlurb, threshold: MetricThreshold(amber: 0.7, red: 0.9)),
            by: \.dataClassScore, descriptor: "Most data", types: metrics.types,
            format: { String(format: "%.0f%%", $0 * 100) })
        typeMetricCard(
            MetricVisual(title: "Nesting Depth", icon: "square.stack.3d.down.right", family: .smell,
                         blurb: Self.nestingDepthBlurb, threshold: MetricThreshold(amber: 3, red: 4)),
            by: \.nestingDepth, descriptor: "Deepest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Overrides", icon: "arrow.uturn.down", family: .smell,
                         blurb: Self.overrideCountBlurb, threshold: MetricThreshold(amber: 4, red: 8)),
            by: \.overrideCount, descriptor: "Most", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Deep & Wide", icon: "arrow.up.and.down.and.arrow.left.and.right",
                         family: .smell, blurb: Self.deepAndWideBlurb,
                         threshold: MetricThreshold(amber: 6, red: 12)),
            by: \.deepAndWide, descriptor: "Hub", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Cohesion (LCOM)", icon: "puzzlepiece", family: .smell,
                         blurb: Self.lackOfCohesionBlurb, threshold: MetricThreshold(amber: 2, red: 4)),
            by: \.lackOfCohesion, descriptor: "Least cohesive", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Feature Envy", icon: "person.2", family: .smell,
                         blurb: Self.featureEnvyBlurb, threshold: MetricThreshold(amber: 1, red: 3)),
            by: \.featureEnvyMethods, descriptor: "Most", types: metrics.types)
    }

    /// Complexity and structural-shape metrics.
    @ViewBuilder
    private func structuralMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: "Cyclomatic Complexity", icon: "arrow.triangle.branch", family: .structural,
                         blurb: Self.cyclomaticComplexityBlurb, threshold: MetricThreshold(amber: 10, red: 20)),
            by: \.maxCyclomaticComplexity, descriptor: "Most branchy", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Properties", icon: "list.bullet.rectangle", family: .structural,
                         blurb: Self.numberOfPropertiesBlurb, threshold: MetricThreshold(amber: 15, red: 25)),
            by: \.numberOfProperties, descriptor: "Most", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Children", icon: "arrow.triangle.pull", family: .structural,
                         blurb: Self.numberOfChildrenBlurb),
            by: \.numberOfChildren, descriptor: "Most subclassed", types: metrics.types)
    }

    /// Title, icon, family band, optional severity threshold, and explanation for a statistics card,
    /// bundled so the card builders stay within the parameter limit. The card's tint is its family's.
    struct MetricVisual {
        let title: String
        let icon: String
        let family: MetricFamily
        let blurb: String
        /// The amber/red guardrails for a directional metric; `nil` for a neutral metric (no dot).
        var threshold: MetricThreshold?
        var color: Color { family.color }
    }

    /// A card for a per-type metric: max/avg with the types achieving the max named in the caption (up
    /// to three, then "and N more"). Tapping opens the full ranked list (`typeDetail`).
    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>,
        descriptor: String, types: [CodeMetrics.TypeMetric]
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { Double($0[keyPath: keyPath]) }
        // Build the ranked drill-down lazily on tap — it sorts every type and resolves each row's
        // source file, so keeping it out of the render path matters when the pane re-lays out.
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(Int(summary.maximum))",
            secondary: String(format: "avg %.1f", summary.average),
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = typeDetail(visual.title, visual.blurb, types, by: keyPath) }
                : nil)
    }

    /// A card for a `Double`-valued per-type metric (a ratio or mean), formatted by `format`. Mirrors
    /// the `Int` overload; tapping opens the full ranked list (`typeDetail`).
    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Double>,
        descriptor: String, types: [CodeMetrics.TypeMetric], format: @escaping (Double) -> String
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { $0[keyPath: keyPath] }
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(format(summary.maximum))",
            secondary: "avg \(format(summary.average))",
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = typeDetail(visual.title, visual.blurb, types, by: keyPath, format: format) }
                : nil)
    }

    /// A card for a per-module metric (`value`), formatted by `format`, with every top-ranked module
    /// named. Tapping opens the ranked module list (`moduleDetail`).
    private func moduleMetricCard(
        _ visual: MetricVisual, descriptor: String, modules: [CodeMetrics.ModuleCoupling],
        value: @escaping (CodeMetrics.ModuleCoupling) -> Double, format: @escaping (Double) -> String
    ) -> MetricStatCard {
        let summary = MetricSummary(modules, value: value)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(format(summary.maximum))",
            secondary: "avg \(format(summary.average))",
            exemplar: caption(descriptor, summary.exemplars.map(\.name)),
            severity: visual.threshold?.severity(for: summary.maximum),
            uniformHeight: statCardHeight,
            blurb: visual.blurb,
            onTap: summary.maximum > 0
                ? { statisticDetail = moduleDetail(visual.title, visual.blurb, modules, value: value, format: format) }
                : nil)
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    /// "`descriptor.lowercased()`: name, name, name and N more" — or `nil` when there are no exemplars.
    /// Names beyond the first three are folded into a trailing count so a large tie stays one short line.
    private func caption(_ descriptor: String, _ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3)
        let remaining = names.count - shown.count
        var list = shown.joined(separator: ", ")
        if remaining > 0 { list += " and \(remaining) more" }
        return "\(descriptor.lowercased()): \(list)"
    }
}
