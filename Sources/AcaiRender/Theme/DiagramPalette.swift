import SwiftUI
import AcaiCore
import AcaiDiagram

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

/// Canvas background and the three ink weights used across every diagram type.
public struct CanvasInkColors: Sendable {
    public var background: Color
    public var primaryInk: Color
    public var secondaryInk: Color
    public var mutedInk: Color

    public init(background: Color, primaryInk: Color, secondaryInk: Color, mutedInk: Color) {
        self.background = background
        self.primaryInk = primaryInk
        self.secondaryInk = secondaryInk
        self.mutedInk = mutedInk
    }
}

/// Relationship line, arrow/diamond decoration fill, and edge-label ink.
public struct EdgeColors: Sendable {
    public var line: Color
    public var decorationFill: Color
    public var labelInk: Color

    public init(line: Color, decorationFill: Color, labelInk: Color) {
        self.line = line
        self.decorationFill = decorationFill
        self.labelInk = labelInk
    }
}

/// Shared border and surface tones used by nodes with no per-kind tint.
public struct NeutralStructureColors: Sendable {
    public var border: Color
    public var subtleSurface: Color

    public init(border: Color, subtleSurface: Color) {
        self.border = border
        self.subtleSurface = subtleSurface
    }
}

/// State-diagram background, choice-pseudostate background, and the solid fill used by
/// initial/final state markers.
public struct StateMachineColors: Sendable {
    public var background: Color
    public var choiceBackground: Color
    public var solidFill: Color

    public init(background: Color, choiceBackground: Color, solidFill: Color) {
        self.background = background
        self.choiceBackground = choiceBackground
        self.solidFill = solidFill
    }
}

/// In-scope/out-of-scope node fills on the call graph canvas.
public struct CallGraphColors: Sendable {
    public var inScopeFill: Color
    public var outOfScopeFill: Color

    public init(inScopeFill: Color, outOfScopeFill: Color) {
        self.inScopeFill = inScopeFill
        self.outOfScopeFill = outOfScopeFill
    }
}

/// Fill, border and (where applicable) icon colours for every freeform-diagram decoration kind.
public struct FreeformDecorationColors: Sendable {
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

    public init(
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
        artifactIcon: Color
    ) {
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
    }
}

/// A container-box variant. A fixed UML concept (the extensibility lives in the *palette*, which
/// chooses each variant's colours — not in this closed set of kinds).
public enum ContainerTint: Sendable {
    case package, boundary, subsystem
}

/// The single source of truth for every diagram node/edge colour, replacing per-view hardcoded
/// literals.
///
/// `DiagramPalette` is an open value type: ``light`` / ``dark`` are just static instances, and
/// third parties can add their own the same way stdlib extends `Color` or `Font` —
/// `extension DiagramPalette { static let solarized = DiagramPalette(...) }`. Colours are grouped
/// into families (``CanvasInkColors``, ``EdgeColors``, ``NeutralStructureColors``,
/// ``StateMachineColors``, ``CallGraphColors``, ``FreeformDecorationColors``), each a small
/// memberwise-initialised struct; adding a colour to a family touches only that family's type.
/// Per-kind families are resolved through `@Sendable` closures, so a custom theme controls them
/// too.
///
/// Views read it from the environment (`EnvironmentValues.diagramPalette`); off-screen snapshot
/// views take it as a parameter.
public struct DiagramPalette: Sendable {

    public var canvasInk: CanvasInkColors
    public var edges: EdgeColors
    public var neutralStructure: NeutralStructureColors
    public var stateMachine: StateMachineColors
    public var callGraph: CallGraphColors
    public var freeformDecorations: FreeformDecorationColors

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
        canvasInk: CanvasInkColors,
        edges: EdgeColors,
        neutralStructure: NeutralStructureColors,
        stateMachine: StateMachineColors,
        callGraph: CallGraphColors,
        freeformDecorations: FreeformDecorationColors,
        exportTheme: DiagramTheme,
        typeColors: @escaping @Sendable (TypeKind) -> KindColors,
        participantColors: @escaping @Sendable (SequenceDiagram.Participant.Kind) -> KindColors,
        containerColors: @escaping @Sendable (ContainerTint) -> ContainerColors
    ) {
        self.canvasInk = canvasInk
        self.edges = edges
        self.neutralStructure = neutralStructure
        self.stateMachine = stateMachine
        self.callGraph = callGraph
        self.freeformDecorations = freeformDecorations
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

    public static func forScheme(_ scheme: ColorScheme) -> DiagramPalette {
        scheme == .dark ? .dark : .light
    }
}
