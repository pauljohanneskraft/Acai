import AcaiCore
import Foundation

/// Reuses a budget's own `max`/`min` as a diagram's fine-to-critical gradient endpoints (backing
/// `acai diagram --color-by`), so colouring a diagram by measurement can never disagree with what
/// actually fails the check — a metric's thresholds live in exactly one place, the same `budgets`
/// entry that already gates it. The colours themselves are fixed and shared app-wide (see
/// `AcaiDiagram.SeverityColors`); a budget only ever describes the codebase, never the view.
extension MetricBudget {
    /// A type's normalised position between this budget's `min` (`0`, "fine") and `max` (`1`,
    /// "critical"), looked up from `colorReadings(for:)`.
    public struct ColorReading: Equatable, Sendable {
        /// `0` at `min` (or `0` when `min` is unset), `1` at `max`, clamped — the fraction a colour
        /// gradient interpolates by.
        public let fraction: Double
        public let value: Double

        /// The value formatted for display next to the colour, so colour is never the only signal: a
        /// whole number prints bare, anything fractional to two decimal places.
        public var formattedValue: String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        }
    }

    /// Every type's normalised reading for this budget's metric, keyed by type id. `nil` when this
    /// budget has no `max` to anchor the critical end of the gradient — a floor-only (`min`-only)
    /// budget can gate a build but can't colour a diagram. Types the metric doesn't apply to (a
    /// module-scoped metric) are omitted so callers fall back to their default styling.
    public func colorReadings(for types: [CodeMetrics.TypeMetric]) -> [String: ColorReading]? {
        guard let critical = max else { return nil }
        let fine = min ?? 0
        let pairs = types.compactMap { type -> (String, ColorReading)? in
            guard let value = metric.value(in: type) else { return nil }
            return (type.id, ColorReading(fraction: fraction(value, fine: fine, critical: critical), value: value))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// `value`'s position between `fine` (0) and `critical` (1), clamped rather than extrapolated.
    /// Handles a budget where `fine` is the larger bound (a "smaller is worse" metric) by normalising
    /// against the signed span instead of assuming `fine < critical`.
    private func fraction(_ value: Double, fine: Double, critical: Double) -> Double {
        guard critical != fine else { return 0 }
        return Swift.min(1, Swift.max(0, (value - fine) / (critical - fine)))
    }
}
