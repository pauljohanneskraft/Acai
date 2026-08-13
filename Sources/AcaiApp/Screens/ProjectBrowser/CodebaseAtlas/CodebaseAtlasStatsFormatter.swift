import AcaiCore
import Foundation

/// Extracts `CodeMetrics`' headline numbers into one text line per metric — the Atlas stats page's
/// content. Mirrors the metric families `CodebaseDetailView+StatisticsCards.swift`'s stat-card grid
/// shows (module coupling, classic OO, code-smell, structural), but as plain "max/avg" text lines
/// rather than rendering the interactive card views flat: the Atlas has no need for the cards'
/// tap-through drill-downs or hover blurbs, only the same underlying numbers. A value you
/// instantiate over one codebase's metrics and read `lines` from.
struct CodebaseAtlasStatsFormatter {
    let metrics: CodeMetrics

    /// How many stat lines fit one Atlas page — chosen so the ~24-line metric set spans a couple of
    /// pages rather than one dense wall of text.
    static let linesPerPage = 12

    var lines: [String] {
        [countsLine] + moduleLines + classicLines + smellLines + structuralLines
    }

    private var countsLine: String {
        let counts = metrics.counts
        return "Types \(counts.totalTypes) · Protocols \(counts.protocols) · Methods \(counts.methods) · " +
            "Properties \(counts.properties) · Relationships \(counts.relationships)"
    }

    private var moduleLines: [String] {
        [
            moduleLine("Instability", format: percent) { $0.instability },
            moduleLine("Abstractness", format: percent) { $0.abstractness },
            moduleLine("Distance (Main Seq.)", format: percent) { $0.distanceFromMainSequence },
            moduleLine("SDP Breaches") { Double($0.stableDependencyViolations.count) },
            moduleLine("Efferent (Ce)") { Double($0.efferentCoupling) },
            moduleLine("Afferent (Ca)") { Double($0.afferentCoupling) }
        ]
    }

    private var classicLines: [String] {
        [
            typeLine("Inheritance Depth") { Double($0.depthOfInheritance) },
            typeLine("Fan-out") { Double($0.fanOut) },
            typeLine("Fan-in") { Double($0.fanIn) },
            typeLine("Methods") { Double($0.weightedMethods) }
        ]
    }

    private var smellLines: [String] {
        [
            typeLine("Response (RFC)") { Double($0.responseForClass) },
            typeLine("Public API", format: percent) { $0.publicMemberRatio },
            typeLine("Mutable Public State") { Double($0.mutablePublicState) },
            typeLine("Parameters") { Double($0.maxParameters) },
            typeLine("Data-class Score", format: percent) { $0.dataClassScore },
            typeLine("Nesting Depth") { Double($0.nestingDepth) },
            typeLine("Overrides") { Double($0.overrideCount) },
            typeLine("Deep & Wide") { Double($0.deepAndWide) },
            typeLine("Cohesion (LCOM)") { Double($0.lackOfCohesion) },
            typeLine("Feature Envy") { Double($0.featureEnvyMethods) }
        ]
    }

    private var structuralLines: [String] {
        [
            typeLine("Cyclomatic Complexity") { Double($0.maxCyclomaticComplexity) },
            typeLine("Properties") { Double($0.numberOfProperties) },
            typeLine("Children") { Double($0.numberOfChildren) }
        ]
    }

    private func moduleLine(
        _ title: String,
        format: @escaping (Double) -> String = { String(Int($0)) },
        _ value: (CodeMetrics.ModuleCoupling) -> Double
    ) -> String {
        let summary = MetricSummary(metrics.modules, value: value)
        return "\(title): max \(format(summary.maximum)) · avg \(format(summary.average))"
    }

    private func typeLine(
        _ title: String,
        format: @escaping (Double) -> String = { String(Int($0)) },
        _ value: (CodeMetrics.TypeMetric) -> Double
    ) -> String {
        let summary = MetricSummary(metrics.types, value: value)
        return "\(title): max \(format(summary.maximum)) · avg \(format(summary.average))"
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
}
