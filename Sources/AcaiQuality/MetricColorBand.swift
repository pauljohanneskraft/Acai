import AcaiCore
import Foundation

/// A continuous colour gradient over one metric's value range, sourced from the rules file so a
/// team's own thresholds — not a settings screen — decide what a diagram's colours mean. `stops`
/// are kept sorted by `value`; a value outside their range clamps to the nearest stop's colour
/// rather than extrapolating.
public struct MetricColorBand: Codable, Equatable, Sendable {
    public struct Stop: Codable, Equatable, Sendable {
        public var value: Double
        public var color: String

        public init(value: Double, color: String) {
            self.value = value
            self.color = color
        }
    }

    /// A type's colour and raw metric value, looked up from `coloring(for:)`.
    public struct Coloring: Equatable, Sendable {
        public let hex: String
        public let value: Double

        /// The value formatted for display next to the colour, so colour is never the only signal:
        /// a whole number prints bare, anything fractional to two decimal places.
        public var formattedValue: String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        }
    }

    public var metric: MetricBudget.Metric
    public var stops: [Stop]

    public init(metric: MetricBudget.Metric, stops: [Stop]) {
        self.metric = metric
        self.stops = stops.sorted { $0.value < $1.value }
    }

    /// Lenient decoding mirrors `MetricBudget`: stops are sorted on decode too, so an author can
    /// list them in any order.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(MetricBudget.Metric.self, forKey: .metric)
        stops = try container.decode([Stop].self, forKey: .stops).sorted { $0.value < $1.value }
    }

    /// The colour for `value`: linear RGB interpolation between the two bounding stops. `nil` when
    /// no stops are defined.
    public func hex(for value: Double) -> String? {
        guard let first = stops.first, let last = stops.last else { return nil }
        guard value > first.value else { return first.color }
        guard value < last.value else { return last.color }
        guard let upperIndex = stops.firstIndex(where: { $0.value >= value }), upperIndex > 0 else {
            return first.color
        }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = upper.value - lower.value
        let fraction = span == 0 ? 0 : (value - lower.value) / span
        return HexColor(lower.color).mixed(with: HexColor(upper.color), fraction: fraction).string
    }

    /// Every type's colour and raw value for this band's metric, keyed by type id — the lookup a
    /// class diagram's node colour override and annotation read. Types the metric doesn't apply to
    /// (e.g. a module-scoped metric) are omitted so callers fall back to their default styling.
    public func coloring(for types: [CodeMetrics.TypeMetric]) -> [String: Coloring] {
        let pairs = types.compactMap { type -> (String, Coloring)? in
            guard let value = metric.value(in: type), let hex = hex(for: value) else { return nil }
            return (type.id, Coloring(hex: hex, value: value))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

/// A parsed `#RRGGBB` colour, private to blending gradient stops — never surfaces beyond a hex
/// string.
private struct HexColor {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mixed(with other: HexColor, fraction: Double) -> HexColor {
        HexColor(
            red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction
        )
    }

    var string: String {
        "#" + [red, green, blue].map { component -> String in
            let byte = max(0, min(255, Int((component * 255).rounded())))
            let hex = String(byte, radix: 16, uppercase: true)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }
}
