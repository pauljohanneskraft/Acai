import AcaiCore

/// Which per-type metric to rank the human metrics table by.
enum MetricsSortKey: String, CaseIterable {
    case fanOut
    case fanIn
    case weightedMethods
    case depthOfInheritance
    case numberOfChildren
    case responseForClass
    case publicMemberCount
    case publicMemberRatio
    case mutablePublicState
    case maxParameters
    case meanParameters
    case dataClassScore
    case overrideCount
    case nestingDepth
    case deepAndWide
    case lackOfCohesion
    case featureEnvyMethods

    // `Double` so ratio/mean/score metrics sort alongside the integer ones through one path. A lookup
    // table rather than a 15-case switch keeps the accessor within the cyclomatic-complexity budget.
    fileprivate func value(_ metric: CodeMetrics.TypeMetric) -> Double {
        Self.accessors[self]?(metric) ?? 0
    }

    private static let accessors: [MetricsSortKey: @Sendable (CodeMetrics.TypeMetric) -> Double] = [
        .fanOut: { Double($0.fanOut) },
        .fanIn: { Double($0.fanIn) },
        .weightedMethods: { Double($0.weightedMethods) },
        .depthOfInheritance: { Double($0.depthOfInheritance) },
        .numberOfChildren: { Double($0.numberOfChildren) },
        .responseForClass: { Double($0.responseForClass) },
        .publicMemberCount: { Double($0.publicMemberCount) },
        .publicMemberRatio: { $0.publicMemberRatio },
        .mutablePublicState: { Double($0.mutablePublicState) },
        .maxParameters: { Double($0.maxParameters) },
        .meanParameters: { $0.meanParameters },
        .dataClassScore: { $0.dataClassScore },
        .overrideCount: { Double($0.overrideCount) },
        .nestingDepth: { Double($0.nestingDepth) },
        .deepAndWide: { Double($0.deepAndWide) },
        .lackOfCohesion: { Double($0.lackOfCohesion) },
        .featureEnvyMethods: { Double($0.featureEnvyMethods) }
    ]
}

/// Renders `CodeMetrics` as a human-readable report: a counts summary, a module table sorted by
/// distance from the main sequence, and a per-type table ranked by a chosen metric. A value you
/// instantiate with the data and ask to `render()`.
struct MetricsTextReport {
    let metrics: CodeMetrics
    let sort: MetricsSortKey
    let top: Int?

    func render() -> String {
        ([summary(), "", moduleTable(), "", typeTable(), "", smellTable()]).joined(separator: "\n")
    }

    private func summary() -> String {
        let c = metrics.counts
        let publicMembers = metrics.modules.reduce(0) { $0 + $1.publicMemberCount }
        return "Types: \(c.totalTypes)  Protocols: \(c.protocols)  Methods: \(c.methods)  "
            + "Properties: \(c.properties)  Relationships: \(c.relationships)  Public API: \(publicMembers)"
    }

    private func moduleTable() -> String {
        let header = "MODULE".paddedTrailing(to: 18) + "types".paddedLeading(to: 6)
            + "I".paddedLeading(to: 7) + "A".paddedLeading(to: 7) + "D".paddedLeading(to: 7)
            + "  Ca".paddedLeading(to: 6) + "  Ce".paddedLeading(to: 6)
        let rows = metrics.modules
            .sorted { $0.distanceFromMainSequence > $1.distanceFromMainSequence }
            .map { module in
                module.name.paddedTrailing(to: 18)
                    + String(module.typeCount).paddedLeading(to: 6)
                    + ratio(module.instability).paddedLeading(to: 7)
                    + ratio(module.abstractness).paddedLeading(to: 7)
                    + ratio(module.distanceFromMainSequence).paddedLeading(to: 7)
                    + String(module.afferentCoupling).paddedLeading(to: 6)
                    + String(module.efferentCoupling).paddedLeading(to: 6)
            }
        return (["Modules (by distance from main sequence):", header] + rows).joined(separator: "\n")
    }

    /// Types sorted by the chosen metric (descending), limited to `top` when set. Shared by both
    /// per-type tables so they present the same rows in the same order.
    private var rankedTypes: [CodeMetrics.TypeMetric] {
        let ranked = metrics.types.sorted { sort.value($0) > sort.value($1) }
        return top.map { Array(ranked.prefix($0)) } ?? ranked
    }

    /// Classic OO metrics per type: fan-out/in, weighted methods, DIT, NOC.
    private func typeTable() -> String {
        let header = "TYPE".paddedTrailing(to: 34) + "MODULE".paddedTrailing(to: 16)
            + "out".paddedLeading(to: 5) + "in".paddedLeading(to: 5) + "wmc".paddedLeading(to: 5)
            + "dit".paddedLeading(to: 5) + "noc".paddedLeading(to: 5)
        let limited = rankedTypes
        let rows = limited.map { metric in
            metric.name.paddedTrailing(to: 34) + metric.module.paddedTrailing(to: 16)
                + String(metric.fanOut).paddedLeading(to: 5) + String(metric.fanIn).paddedLeading(to: 5)
                + String(metric.weightedMethods).paddedLeading(to: 5)
                + String(metric.depthOfInheritance).paddedLeading(to: 5)
                + String(metric.numberOfChildren).paddedLeading(to: 5)
        }
        return (["Types (by \(sort.rawValue), top \(limited.count)):", header] + rows).joined(separator: "\n")
    }

    /// Code-smell metrics per type, kept in a second table so neither exceeds the 120-column budget:
    /// RFC, public API surface (count + %), mutable public state, widest signature, data-class score,
    /// nesting depth, override count, lack of cohesion (LCOM), and feature-envy method count.
    private func smellTable() -> String {
        let header = "TYPE".paddedTrailing(to: 34) + "MODULE".paddedTrailing(to: 16)
            + "rfc".paddedLeading(to: 5) + "pub".paddedLeading(to: 5) + "pub%".paddedLeading(to: 6)
            + "mut".paddedLeading(to: 5) + "par".paddedLeading(to: 5) + "data".paddedLeading(to: 6)
            + "nest".paddedLeading(to: 5) + "ovr".paddedLeading(to: 5) + "lcom".paddedLeading(to: 5)
            + "envy".paddedLeading(to: 5)
        let limited = rankedTypes
        let rows = limited.map { metric in
            metric.name.paddedTrailing(to: 34) + metric.module.paddedTrailing(to: 16)
                + String(metric.responseForClass).paddedLeading(to: 5)
                + String(metric.publicMemberCount).paddedLeading(to: 5)
                + percent(metric.publicMemberRatio).paddedLeading(to: 6)
                + String(metric.mutablePublicState).paddedLeading(to: 5)
                + String(metric.maxParameters).paddedLeading(to: 5)
                + percent(metric.dataClassScore).paddedLeading(to: 6)
                + String(metric.nestingDepth).paddedLeading(to: 5)
                + String(metric.overrideCount).paddedLeading(to: 5)
                + String(metric.lackOfCohesion).paddedLeading(to: 5)
                + String(metric.featureEnvyMethods).paddedLeading(to: 5)
        }
        return (["Code smells (by \(sort.rawValue), top \(limited.count)):", header] + rows).joined(separator: "\n")
    }

    private func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
