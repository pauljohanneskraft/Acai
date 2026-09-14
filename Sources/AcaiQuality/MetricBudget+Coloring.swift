import AcaiCore
import Foundation

extension MetricBudget {
    public struct ColorReading: Equatable, Sendable {
        public let fraction: Double
        public let value: Double

        public var formattedValue: String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        }
    }

    /// `nil` when this budget has no `max` to anchor the critical end of the gradient.
    public func colorReadings(for types: [CodeMetrics.TypeMetric]) -> [String: ColorReading]? {
        guard let critical = max else { return nil }
        let fine = min ?? 0
        let pairs = types.compactMap { type -> (String, ColorReading)? in
            guard let value = metric.value(in: type) else { return nil }
            return (type.id, ColorReading(fraction: fraction(value, fine: fine, critical: critical), value: value))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func fraction(_ value: Double, fine: Double, critical: Double) -> Double {
        guard critical != fine else { return 0 }
        return Swift.min(1, Swift.max(0, (value - fine) / (critical - fine)))
    }
}
