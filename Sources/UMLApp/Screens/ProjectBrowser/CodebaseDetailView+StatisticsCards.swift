import SwiftUI
import UMLCore

// The statistics section and its stat-card builders. Kept in a separate file (same module) so
// `CodebaseDetailView.swift` stays within SwiftLint's `file_length`.
extension CodebaseDetailView {

    // MARK: - Statistics

    func statisticsSection(artifact: CodeArtifact) -> some View {
        let metrics = artifact.computeMetrics()
        return CollapsibleSection(title: "Statistics") {
            LazyVGrid(columns: cardColumns(count: 4), spacing: 12) {
                classicMetricCards(metrics: metrics)
                smellMetricCards(metrics: metrics)
            }
            .padding(.horizontal)
            .onPreferenceChange(CardHeightPreferenceKey.self) { height in
                if abs(statCardHeight - height) > 0.5 { statCardHeight = height }
            }
        }
    }

    /// Per-module coupling and the classic OO metrics (DIT/fan/WMC).
    @ViewBuilder
    private func classicMetricCards(metrics: CodeMetrics) -> some View {
        moduleMetricCard(
            MetricVisual(title: "Instability", icon: "tornado", color: .orange, blurb: Self.instabilityBlurb),
            descriptor: "Most unstable", modules: metrics.modules)
        typeMetricCard(
            MetricVisual(title: "Inheritance Depth", icon: "arrow.down.to.line", color: .blue,
                         blurb: Self.inheritanceDepthBlurb),
            by: \.depthOfInheritance, descriptor: "Deepest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Fan-out", icon: "arrow.up.right", color: .purple, blurb: Self.fanOutBlurb),
            by: \.fanOut, descriptor: "Most coupled", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Fan-in", icon: "arrow.down.left", color: .green, blurb: Self.fanInBlurb),
            by: \.fanIn, descriptor: "Hotspot", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Methods", icon: "function", color: .pink,
                         blurb: Self.weightedMethodsBlurb),
            by: \.weightedMethods, descriptor: "Largest", types: metrics.types)
    }

    /// The code-smell folds (issue #101).
    @ViewBuilder
    private func smellMetricCards(metrics: CodeMetrics) -> some View {
        typeMetricCard(
            MetricVisual(title: "Response (RFC)", icon: "arrow.triangle.branch", color: .teal,
                         blurb: Self.responseForClassBlurb),
            by: \.responseForClass, descriptor: "Largest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Public API", icon: "lock.open", color: .indigo,
                         blurb: Self.publicSurfaceBlurb),
            by: \.publicMemberRatio, descriptor: "Widest", types: metrics.types,
            format: { String(format: "%.0f%%", $0 * 100) })
        typeMetricCard(
            MetricVisual(title: "Mutable Public State", icon: "pencil.and.outline", color: .red,
                         blurb: Self.mutablePublicStateBlurb),
            by: \.mutablePublicState, descriptor: "Most", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Parameters", icon: "slider.horizontal.3", color: .cyan,
                         blurb: Self.parametersBlurb),
            by: \.maxParameters, descriptor: "Widest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Data-class Score", icon: "tablecells", color: .brown,
                         blurb: Self.dataClassScoreBlurb),
            by: \.dataClassScore, descriptor: "Most data", types: metrics.types,
            format: { String(format: "%.0f%%", $0 * 100) })
        typeMetricCard(
            MetricVisual(title: "Nesting Depth", icon: "square.stack.3d.down.right", color: .mint,
                         blurb: Self.nestingDepthBlurb),
            by: \.nestingDepth, descriptor: "Deepest", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Overrides", icon: "arrow.uturn.down", color: .yellow,
                         blurb: Self.overrideCountBlurb),
            by: \.overrideCount, descriptor: "Most", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Deep & Wide", icon: "arrow.up.and.down.and.arrow.left.and.right",
                         color: .gray, blurb: Self.deepAndWideBlurb),
            by: \.deepAndWide, descriptor: "Hub", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Cohesion (LCOM)", icon: "puzzlepiece", color: .orange,
                         blurb: Self.lackOfCohesionBlurb),
            by: \.lackOfCohesion, descriptor: "Least cohesive", types: metrics.types)
        typeMetricCard(
            MetricVisual(title: "Feature Envy", icon: "person.2", color: .pink,
                         blurb: Self.featureEnvyBlurb),
            by: \.featureEnvyMethods, descriptor: "Most", types: metrics.types)
    }

    /// Title, icon, tint, and explanation for a statistics card, bundled so the card builders stay
    /// within the parameter limit.
    struct MetricVisual {
        let title: String
        let icon: String
        let color: Color
        let blurb: String
    }

    /// A card for a per-type metric: max/avg with the types achieving the max named in the caption (up
    /// to three, then "and N more"). Tapping opens the full ranked list (`typeDetail`).
    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>,
        descriptor: String, types: [CodeMetrics.TypeMetric]
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { Double($0[keyPath: keyPath]) }
        let detail = typeDetail(visual.title, visual.blurb, types, by: keyPath)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(Int(summary.maximum))",
            secondary: String(format: "avg %.1f", summary.average),
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            uniformHeight: statCardHeight,
            onTap: detail.rows.isEmpty ? nil : { statisticDetail = detail })
    }

    /// A card for a `Double`-valued per-type metric (a ratio or mean), formatted by `format`. Mirrors
    /// the `Int` overload; tapping opens the full ranked list (`typeDetail`).
    private func typeMetricCard(
        _ visual: MetricVisual,
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Double>,
        descriptor: String, types: [CodeMetrics.TypeMetric], format: (Double) -> String
    ) -> MetricStatCard {
        let summary = MetricSummary(types) { $0[keyPath: keyPath] }
        let detail = typeDetail(visual.title, visual.blurb, types, by: keyPath, format: format)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: "max \(format(summary.maximum))",
            secondary: "avg \(format(summary.average))",
            exemplar: caption(descriptor, summary.exemplars.map { shortName($0.name) }),
            uniformHeight: statCardHeight,
            onTap: detail.rows.isEmpty ? nil : { statisticDetail = detail })
    }

    /// A card for the per-module instability metric, rendered as a percentage with every most-unstable
    /// module named. Tapping opens the ranked module list (`moduleDetail`).
    private func moduleMetricCard(
        _ visual: MetricVisual,
        descriptor: String, modules: [CodeMetrics.ModuleCoupling]
    ) -> MetricStatCard {
        let summary = MetricSummary(modules) { $0.instability }
        let detail = moduleDetail(visual.title, visual.blurb, modules)
        return MetricStatCard(
            title: visual.title,
            icon: visual.icon,
            color: visual.color,
            primary: String(format: "max %.0f%%", summary.maximum * 100),
            secondary: String(format: "avg %.0f%%", summary.average * 100),
            exemplar: caption(descriptor, summary.exemplars.map(\.name)),
            uniformHeight: statCardHeight,
            onTap: detail.rows.isEmpty ? nil : { statisticDetail = detail })
    }

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
