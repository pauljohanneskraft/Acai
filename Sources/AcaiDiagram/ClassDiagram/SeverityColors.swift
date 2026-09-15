/// Shares its green/red with `DeltaEdgeColors`' added/removed.
public struct SeverityColors: Sendable {
    public let fine: String
    public let medium: String
    public let critical: String

    public init(fine: String = "#2e7d32", medium: String = "#f9a825", critical: String = "#c62828") {
        self.fine = fine
        self.medium = medium
        self.critical = critical
    }

    public static let standard = SeverityColors()

    public func hex(atFraction fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        if clamped <= 0.5 {
            return HexColor(fine).mixed(with: HexColor(medium), fraction: clamped / 0.5).string
        }
        return HexColor(medium).mixed(with: HexColor(critical), fraction: (clamped - 0.5) / 0.5).string
    }
}

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
