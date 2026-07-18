import SwiftUI

private struct DiagramPaletteKey: EnvironmentKey {
    static let defaultValue = DiagramPalette.light
}

public extension EnvironmentValues {
    /// The active diagram colour palette. Canvases inject the theme-resolved palette at their
    /// root; node and edge views read it instead of hardcoding colours.
    var diagramPalette: DiagramPalette {
        get { self[DiagramPaletteKey.self] }
        set { self[DiagramPaletteKey.self] = newValue }
    }
}
