import SwiftUI
import AcaiCore
import AcaiDiagram

/// Builds the bundled ``DiagramPalette/light`` and ``DiagramPalette/dark`` themes. Light values
/// are the app's established pastels; dark values are derived from each family's base hue so the
/// whole set shifts together. Third-party themes don't go through here — they construct a
/// `DiagramPalette` directly.
extension DiagramPalette {

    static func make(isDark: Bool) -> DiagramPalette {
        let typeColors: @Sendable (TypeKind) -> KindColors = { builtinKindColors(Tint($0), isDark: isDark) }
        let participantColors: @Sendable (SequenceDiagram.Participant.Kind) -> KindColors = {
            builtinKindColors(Tint($0), isDark: isDark)
        }
        let containerColors: @Sendable (ContainerTint) -> ContainerColors = {
            builtinContainerColors($0, isDark: isDark)
        }

        return DiagramPalette(
            canvasBackground: isDark ? Color(white: 0.12) : .white,
            primaryInk: isDark ? Color(white: 0.92) : Color(white: 0.10),
            secondaryInk: isDark ? Color(white: 0.82) : Color(white: 0.15),
            mutedInk: isDark ? Color(white: 0.60) : Color(white: 0.35),
            edgeLine: isDark ? Color(white: 0.62) : Color(white: 0.40),
            edgeDecorationFill: isDark ? Color(white: 0.18) : Color(white: 0.96),
            edgeLabelInk: isDark ? Color(white: 0.82) : Color(white: 0.15),
            neutralBorder: isDark ? Color(white: 0.55) : Color(white: 0.45),
            subtleSurface: isDark ? Color(white: 0.20) : Color(white: 0.93),
            stateBackground: builtinKindColors(.blue, isDark: isDark).header,
            choiceBackground: tone(isDark, dark: (0.11, 0.30, 0.28), light: rgb(1.0, 0.98, 0.9)),
            stateSolidFill: isDark ? Color(white: 0.82) : Color(white: 0.15),
            callGraphInScopeFill: builtinKindColors(.blue, isDark: isDark).header,
            callGraphOutOfScopeFill: isDark ? Color(white: 0.22) : Color(white: 0.96),
            useCaseFill: tone(isDark, dark: (0.70, 0.30, 0.26), light: rgb(0.96, 0.95, 1.0)),
            useCaseBorder: tone(isDark, dark: (0.70, 0.42, 0.70), light: rgb(0.58, 0.52, 0.82)),
            noteFill: tone(isDark, dark: (0.13, 0.28, 0.26), light: rgb(1.0, 0.99, 0.94)),
            noteBorder: tone(isDark, dark: (0.13, 0.45, 0.68), light: rgb(0.82, 0.75, 0.42)),
            methodFill: builtinKindColors(.blue, isDark: isDark).header,
            methodBorder: isDark ? Color(white: 0.50) : Color(white: 0.60),
            actorFill: tone(isDark, dark: (0.50, 0.24, 0.24), light: rgb(0.95, 0.99, 0.99)),
            actorBorder: tone(isDark, dark: (0.50, 0.40, 0.68), light: rgb(0.45, 0.72, 0.72)),
            actorIcon: tone(isDark, dark: (0.50, 0.46, 0.80), light: rgb(0.30, 0.60, 0.60)),
            databaseFill: tone(isDark, dark: (0.97, 0.24, 0.26), light: rgb(1.0, 0.96, 0.97)),
            databaseBorder: tone(isDark, dark: (0.97, 0.42, 0.70), light: rgb(0.82, 0.52, 0.58)),
            databaseIcon: tone(isDark, dark: (0.97, 0.48, 0.80), light: rgb(0.72, 0.40, 0.48)),
            artifactFill: tone(isDark, dark: (0.53, 0.24, 0.25), light: rgb(0.95, 0.98, 0.99)),
            artifactBorder: tone(isDark, dark: (0.53, 0.42, 0.70), light: rgb(0.40, 0.65, 0.75)),
            artifactIcon: tone(isDark, dark: (0.53, 0.48, 0.80), light: rgb(0.30, 0.55, 0.65)),
            exportTheme: isDark ? .dark : .default,
            typeColors: typeColors,
            participantColors: participantColors,
            containerColors: containerColors
        )
    }

    /// A themed colour: the authored `light` value, or a hue/saturation/brightness shade in dark.
    private static func tone(_ isDark: Bool, dark: (Double, Double, Double), light: Color) -> Color {
        isDark ? Color(hue: dark.0, saturation: dark.1, brightness: dark.2) : light
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }

    /// Light = authored pastels; dark = derived from the tint's hue.
    private static func builtinKindColors(_ tint: Tint, isDark: Bool) -> KindColors {
        KindColors(
            header: isDark ? tint.derived(saturation: 0.30, brightness: 0.26) : tint.lightHeader,
            body: isDark ? tint.derived(saturation: 0.18, brightness: 0.18) : tint.lightBody,
            border: isDark ? tint.derived(saturation: 0.40, brightness: 0.66) : tint.lightBorder,
            accent: isDark ? tint.derived(saturation: 0.55, brightness: 0.90) : tint.lightAccent
        )
    }

    private static func builtinContainerColors(_ container: ContainerTint, isDark: Bool) -> ContainerColors {
        guard isDark else {
            switch container {
            case .package:
                return ContainerColors(
                    fill: Color(red: 0.96, green: 0.93, blue: 0.88),
                    header: Color(red: 0.91, green: 0.86, blue: 0.78),
                    border: Color(red: 0.68, green: 0.58, blue: 0.42))
            case .boundary:
                return ContainerColors(
                    fill: Color(red: 1.0, green: 0.97, blue: 0.90),
                    header: Color(red: 0.96, green: 0.92, blue: 0.82),
                    border: Color(red: 0.78, green: 0.65, blue: 0.35))
            case .subsystem:
                return ContainerColors(
                    fill: Color(red: 0.90, green: 0.96, blue: 0.98),
                    header: Color(red: 0.82, green: 0.92, blue: 0.96),
                    border: Color(red: 0.40, green: 0.65, blue: 0.75))
            }
        }
        let hue: Double
        switch container {
        case .package:
            hue = 0.09
        case .boundary:
            hue = 0.11
        case .subsystem:
            hue = 0.53
        }
        return ContainerColors(
            fill: Color(hue: hue, saturation: 0.26, brightness: 0.22),
            header: Color(hue: hue, saturation: 0.32, brightness: 0.30),
            border: Color(hue: hue, saturation: 0.42, brightness: 0.68))
    }
}
