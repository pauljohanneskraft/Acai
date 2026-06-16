import SwiftUI
import UMLCore
import UMLDiagram

/// The four tints that make up a kind-styled node (class box, sequence participant header).
public struct KindColors: Sendable {
    public var header: Color
    public var body: Color
    public var border: Color
    public var accent: Color

    public init(header: Color, body: Color, border: Color, accent: Color) {
        self.header = header
        self.body = body
        self.border = border
        self.accent = accent
    }
}

/// The fill / header / border of a container box.
public struct ContainerColors: Sendable {
    public var fill: Color
    public var header: Color
    public var border: Color

    public init(fill: Color, header: Color, border: Color) {
        self.fill = fill
        self.header = header
        self.border = border
    }
}

/// A container-box variant. A fixed UML concept (the extensibility lives in the *palette*, which
/// chooses each variant's colours — not in this closed set of kinds).
public enum ContainerTint: Sendable {
    case package, boundary, subsystem
}

/// The single source of truth for every diagram node/edge colour, replacing the per-view
/// hardcoded literals.
///
/// `DiagramPalette` is an open value type: the bundled ``light`` / ``dark`` are static instances,
/// and third parties can add their own themes the same way the standard library extends `Color`
/// or `Font` — `extension DiagramPalette { static let solarized = DiagramPalette(...) }` — or by
/// copying a bundled palette and tweaking its `var` properties. The per-kind families are
/// resolved through `@Sendable` closures, so a custom theme controls them too.
///
/// Views read it from the environment (``EnvironmentValues/diagramPalette``); off-screen snapshot
/// views take it as a parameter. ``exportTheme`` bridges it to the DOT/Mermaid ``DiagramTheme`` so
/// the chosen theme also drives exports.
public struct DiagramPalette: Sendable {

    // MARK: Canvas & ink

    public var canvasBackground: Color
    public var primaryInk: Color
    public var secondaryInk: Color
    public var mutedInk: Color

    // MARK: Edges

    public var edgeLine: Color
    public var edgeDecorationFill: Color
    public var edgeLabelInk: Color

    // MARK: Neutral structure

    public var neutralBorder: Color
    public var subtleSurface: Color

    // MARK: State machine

    public var stateBackground: Color
    public var choiceBackground: Color
    public var stateSolidFill: Color

    // MARK: Call graph

    public var callGraphInScopeFill: Color
    public var callGraphOutOfScopeFill: Color

    // MARK: Freeform decorations

    public var useCaseFill: Color
    public var useCaseBorder: Color
    public var noteFill: Color
    public var noteBorder: Color
    public var methodFill: Color
    public var methodBorder: Color
    public var actorFill: Color
    public var actorBorder: Color
    public var actorIcon: Color
    public var databaseFill: Color
    public var databaseBorder: Color
    public var databaseIcon: Color
    public var artifactFill: Color
    public var artifactBorder: Color
    public var artifactIcon: Color

    // MARK: Per-kind families

    /// Class-diagram colours for a `TypeKind`.
    public var typeColors: @Sendable (TypeKind) -> KindColors
    /// Sequence-diagram header colours for a participant role.
    public var participantColors: @Sendable (SequenceDiagram.Participant.Kind) -> KindColors
    /// Container-box colours for a variant.
    public var containerColors: @Sendable (ContainerTint) -> ContainerColors

    // MARK: Export bridge

    /// The DOT/Mermaid palette matching this theme, so in-app exports carry the same look.
    public var exportTheme: DiagramTheme

    public init(
        canvasBackground: Color,
        primaryInk: Color,
        secondaryInk: Color,
        mutedInk: Color,
        edgeLine: Color,
        edgeDecorationFill: Color,
        edgeLabelInk: Color,
        neutralBorder: Color,
        subtleSurface: Color,
        stateBackground: Color,
        choiceBackground: Color,
        stateSolidFill: Color,
        callGraphInScopeFill: Color,
        callGraphOutOfScopeFill: Color,
        useCaseFill: Color,
        useCaseBorder: Color,
        noteFill: Color,
        noteBorder: Color,
        methodFill: Color,
        methodBorder: Color,
        actorFill: Color,
        actorBorder: Color,
        actorIcon: Color,
        databaseFill: Color,
        databaseBorder: Color,
        databaseIcon: Color,
        artifactFill: Color,
        artifactBorder: Color,
        artifactIcon: Color,
        exportTheme: DiagramTheme,
        typeColors: @escaping @Sendable (TypeKind) -> KindColors,
        participantColors: @escaping @Sendable (SequenceDiagram.Participant.Kind) -> KindColors,
        containerColors: @escaping @Sendable (ContainerTint) -> ContainerColors
    ) {
        self.canvasBackground = canvasBackground
        self.primaryInk = primaryInk
        self.secondaryInk = secondaryInk
        self.mutedInk = mutedInk
        self.edgeLine = edgeLine
        self.edgeDecorationFill = edgeDecorationFill
        self.edgeLabelInk = edgeLabelInk
        self.neutralBorder = neutralBorder
        self.subtleSurface = subtleSurface
        self.stateBackground = stateBackground
        self.choiceBackground = choiceBackground
        self.stateSolidFill = stateSolidFill
        self.callGraphInScopeFill = callGraphInScopeFill
        self.callGraphOutOfScopeFill = callGraphOutOfScopeFill
        self.useCaseFill = useCaseFill
        self.useCaseBorder = useCaseBorder
        self.noteFill = noteFill
        self.noteBorder = noteBorder
        self.methodFill = methodFill
        self.methodBorder = methodBorder
        self.actorFill = actorFill
        self.actorBorder = actorBorder
        self.actorIcon = actorIcon
        self.databaseFill = databaseFill
        self.databaseBorder = databaseBorder
        self.databaseIcon = databaseIcon
        self.artifactFill = artifactFill
        self.artifactBorder = artifactBorder
        self.artifactIcon = artifactIcon
        self.exportTheme = exportTheme
        self.typeColors = typeColors
        self.participantColors = participantColors
        self.containerColors = containerColors
    }

    // MARK: - Convenience accessors

    public func headerBackground(for kind: TypeKind) -> Color { typeColors(kind).header }
    public func bodyBackground(for kind: TypeKind) -> Color { typeColors(kind).body }
    public func border(for kind: TypeKind) -> Color { typeColors(kind).border }
    public func accent(for kind: TypeKind) -> Color { typeColors(kind).accent }

    public func participantFill(for kind: SequenceDiagram.Participant.Kind) -> Color {
        participantColors(kind).header
    }
    public func participantBorder(for kind: SequenceDiagram.Participant.Kind) -> Color {
        participantColors(kind).border
    }
    public func participantAccent(for kind: SequenceDiagram.Participant.Kind) -> Color {
        participantColors(kind).accent
    }

    public func containerFill(_ container: ContainerTint) -> Color { containerColors(container).fill }
    public func containerHeader(_ container: ContainerTint) -> Color { containerColors(container).header }
    public func containerBorder(_ container: ContainerTint) -> Color { containerColors(container).border }

    // MARK: - Bundled themes

    public static let light = make(isDark: false)
    public static let dark = make(isDark: true)

    /// The bundled palette matching a SwiftUI colour scheme.
    public static func forScheme(_ scheme: ColorScheme) -> DiagramPalette {
        scheme == .dark ? .dark : .light
    }
}
