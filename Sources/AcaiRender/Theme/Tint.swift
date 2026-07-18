import SwiftUI
import AcaiCore
import AcaiDiagram

/// A colour family shared by class-diagram kinds and sequence-diagram roles. It owns its
/// authored light pastels and the base `hue` from which `DiagramPalette` derives dark shades,
/// so every consumer of a given family stays visually consistent.
enum Tint {
    case blue, green, orange, purple, indigo, teal, neutral

    init(_ kind: TypeKind) {
        switch kind {
        case .protocol, .interface:
            self = .blue
        case .struct, .record:
            self = .green
        case .enum:
            self = .orange
        case .class:
            self = .purple
        case .trait:
            self = .teal
        case .mixin:
            self = .indigo
        default:
            self = .neutral
        }
    }

    init(_ kind: SequenceDiagram.Participant.Kind) {
        switch kind {
        case .object:
            self = .neutral
        case .actor:
            self = .blue
        case .boundary:
            self = .purple
        case .control:
            self = .orange
        case .entity:
            self = .green
        case .database:
            self = .teal
        }
    }

    /// Base hue (0...1), or `nil` for the neutral (grey) family.
    private var hue: Double? {
        switch self {
        case .blue:
            0.60
        case .green:
            0.33
        case .orange:
            0.08
        case .purple:
            0.78
        case .indigo:
            0.70
        case .teal:
            0.50
        case .neutral:
            nil
        }
    }

    /// A shade of this tint at the given saturation/brightness — used for dark-mode derivation.
    /// The neutral family collapses to a matching grey.
    func derived(saturation: Double, brightness: Double) -> Color {
        guard let hue else { return Color(white: brightness) }
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    var lightHeader: Color {
        switch self {
        case .blue:
            Color(red: 0.93, green: 0.95, blue: 1.0)
        case .green:
            Color(red: 0.93, green: 0.98, blue: 0.93)
        case .orange:
            Color(red: 1.0, green: 0.96, blue: 0.92)
        case .purple:
            Color(red: 0.96, green: 0.93, blue: 1.0)
        case .indigo:
            Color(red: 0.95, green: 0.93, blue: 1.0)
        case .teal:
            Color(red: 0.92, green: 0.98, blue: 0.98)
        case .neutral:
            Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }

    var lightBody: Color {
        switch self {
        case .blue:
            Color(red: 0.97, green: 0.98, blue: 1.0)
        case .green:
            Color(red: 0.97, green: 0.99, blue: 0.97)
        case .orange:
            Color(red: 1.0, green: 0.99, blue: 0.97)
        case .purple:
            Color(red: 0.99, green: 0.97, blue: 1.0)
        case .indigo:
            Color(red: 0.98, green: 0.97, blue: 1.0)
        case .teal:
            Color(red: 0.97, green: 0.99, blue: 0.99)
        case .neutral:
            Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }

    var lightBorder: Color {
        switch self {
        case .blue:
            Color(red: 0.55, green: 0.62, blue: 0.85)
        case .green:
            Color(red: 0.50, green: 0.72, blue: 0.50)
        case .orange:
            Color(red: 0.82, green: 0.68, blue: 0.45)
        case .purple:
            Color(red: 0.68, green: 0.52, blue: 0.82)
        case .indigo:
            Color(red: 0.58, green: 0.52, blue: 0.82)
        case .teal:
            Color(red: 0.45, green: 0.72, blue: 0.72)
        case .neutral:
            Color(red: 0.70, green: 0.70, blue: 0.70)
        }
    }

    var lightAccent: Color {
        switch self {
        case .blue:
            .blue
        case .green:
            .green
        case .orange:
            .orange
        case .purple:
            .purple
        case .indigo:
            .indigo
        case .teal:
            .teal
        case .neutral:
            .gray
        }
    }
}
