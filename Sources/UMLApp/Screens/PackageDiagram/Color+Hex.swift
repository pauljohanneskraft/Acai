import SwiftUI

extension Color {
    /// Builds a color from a `#rrggbb` hex string (the form `PackageDependencyDiagram.Node.zoneColorHex`
    /// produces). Falls back to clear for malformed input so a bad string can't crash the canvas.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .clear
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
