import SwiftUI

extension Color {
    /// Creates a colour from a `#rrggbb` (or `rrggbb`) hex string, falling back to gray on a
    /// malformed value. Used by the package snapshot to match the `zoneColorHex` tints shared
    /// with the DOT/Mermaid exporters.
    public init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
