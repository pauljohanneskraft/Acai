import UMLCore

/// Which per-type metric to rank the human metrics table by.
enum MetricsSortKey: String, CaseIterable {
    case fanOut
    case fanIn
    case weightedMethods
    case depthOfInheritance
    case numberOfChildren

    fileprivate func value(_ metric: CodeMetrics.TypeMetric) -> Int {
        switch self {
        case .fanOut:
            return metric.fanOut
        case .fanIn:
            return metric.fanIn
        case .weightedMethods:
            return metric.weightedMethods
        case .depthOfInheritance:
            return metric.depthOfInheritance
        case .numberOfChildren:
            return metric.numberOfChildren
        }
    }
}

/// Renders `CodeMetrics` as a human-readable report: a counts summary, a module table sorted by
/// distance from the main sequence, and a per-type table ranked by a chosen metric. A value you
/// instantiate with the data and ask to `render()`.
struct MetricsTextReport {
    let metrics: CodeMetrics
    let sort: MetricsSortKey
    let top: Int?

    func render() -> String {
        ([summary(), "", moduleTable(), "", typeTable()]).joined(separator: "\n")
    }

    private func summary() -> String {
        let c = metrics.counts
        return "Types: \(c.totalTypes)  Protocols: \(c.protocols)  Methods: \(c.methods)  "
            + "Properties: \(c.properties)  Relationships: \(c.relationships)"
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

    private func typeTable() -> String {
        let header = "TYPE".paddedTrailing(to: 34) + "MODULE".paddedTrailing(to: 16)
            + "out".paddedLeading(to: 5) + "in".paddedLeading(to: 5) + "wmc".paddedLeading(to: 5)
            + "dit".paddedLeading(to: 5) + "noc".paddedLeading(to: 5)
        let ranked = metrics.types.sorted { sort.value($0) > sort.value($1) }
        let limited = top.map { Array(ranked.prefix($0)) } ?? ranked
        let rows = limited.map { metric in
            metric.name.paddedTrailing(to: 34) + metric.module.paddedTrailing(to: 16)
                + String(metric.fanOut).paddedLeading(to: 5) + String(metric.fanIn).paddedLeading(to: 5)
                + String(metric.weightedMethods).paddedLeading(to: 5)
                + String(metric.depthOfInheritance).paddedLeading(to: 5)
                + String(metric.numberOfChildren).paddedLeading(to: 5)
        }
        return (["Types (by \(sort.rawValue), top \(limited.count)):", header] + rows).joined(separator: "\n")
    }

    private func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
