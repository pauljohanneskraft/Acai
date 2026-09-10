import AcaiCore
import Foundation

/// Where a metric's value sits between "fine" and "critical", sourced from the rules file so a
/// team's own thresholds — not a settings screen — decide what a diagram's colours mean. The
/// colours themselves are fixed and shared app-wide (see `AcaiDiagram.SeverityColors`); a band only
/// overrides the value at which a metric counts as fine or critical, the same way a budget overrides
/// what counts as a breach.
public struct MetricColorBand: Codable, Equatable, Sendable {
    /// A type's normalised position on the gradient and raw metric value, looked up from
    /// `readings(for:)`.
    public struct Reading: Equatable, Sendable {
        /// `0` at `fine`, `1` at `critical`, clamped — the fraction a colour gradient interpolates by.
        public let fraction: Double
        public let value: Double

        /// The value formatted for display next to the colour, so colour is never the only signal:
        /// a whole number prints bare, anything fractional to two decimal places.
        public var formattedValue: String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        }
    }

    public var metric: MetricBudget.Metric
    public var fine: Double
    public var critical: Double

    public init(metric: MetricBudget.Metric, fine: Double, critical: Double) {
        self.metric = metric
        self.fine = fine
        self.critical = critical
    }

    /// Every type's normalised reading for this band's metric, keyed by type id — the lookup a
    /// class diagram's node colour override and annotation read. Types the metric doesn't apply to
    /// (e.g. a module-scoped metric) are omitted so callers fall back to their default styling.
    public func readings(for types: [CodeMetrics.TypeMetric]) -> [String: Reading] {
        let pairs = types.compactMap { type -> (String, Reading)? in
            guard let value = metric.value(in: type) else { return nil }
            return (type.id, Reading(fraction: fraction(for: value), value: value))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// `value`'s position between `fine` (0) and `critical` (1), clamped rather than extrapolated.
    /// Handles a band where `fine` is the larger bound (a "smaller is worse" metric) by normalising
    /// against the signed span instead of assuming `fine < critical`.
    private func fraction(for value: Double) -> Double {
        guard critical != fine else { return 0 }
        return min(1, max(0, (value - fine) / (critical - fine)))
    }
}
