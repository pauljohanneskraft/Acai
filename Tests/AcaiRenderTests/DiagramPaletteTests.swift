import Testing
import SwiftUI
@testable import AcaiRender
import AcaiCore
import AcaiDiagram

@Suite("Diagram Palette")
struct DiagramPaletteTests {

    @Test func bundledThemesBridgeToExportThemes() {
        #expect(DiagramPalette.light.exportTheme.backgroundColor == DiagramTheme.default.backgroundColor)
        #expect(DiagramPalette.dark.exportTheme.backgroundColor == DiagramTheme.dark.backgroundColor)
    }

    @Test func lightAndDarkDifferPerKind() {
        #expect(DiagramPalette.light.headerBackground(for: .class)
            != DiagramPalette.dark.headerBackground(for: .class))
        #expect(DiagramPalette.light.canvasInk.background != DiagramPalette.dark.canvasInk.background)
    }

    @Test func forSchemeSelectsBundledTheme() {
        #expect(DiagramPalette.forScheme(.dark).canvasInk.background == DiagramPalette.dark.canvasInk.background)
        #expect(DiagramPalette.forScheme(.light).canvasInk.background == DiagramPalette.light.canvasInk.background)
    }

    @Test func paletteIsConsumerExtensible() {
        var tweaked = DiagramPalette.light
        tweaked.canvasInk.background = .black
        #expect(tweaked.canvasInk.background == Color.black)

        let solid = KindColors(header: .red, body: .red, border: .red, accent: .red)
        let scratch = DiagramPalette(
            canvasInk: CanvasInkColors(background: .black, primaryInk: .white, secondaryInk: .white, mutedInk: .gray),
            edges: EdgeColors(line: .white, decorationFill: .black, labelInk: .white),
            neutralStructure: NeutralStructureColors(border: .gray, subtleSurface: .black),
            stateMachine: StateMachineColors(background: .red, choiceBackground: .red, solidFill: .white),
            callGraph: CallGraphColors(inScopeFill: .red, outOfScopeFill: .black),
            freeformDecorations: FreeformDecorationColors(
                useCaseFill: .red, useCaseBorder: .red,
                noteFill: .red, noteBorder: .red,
                methodFill: .red, methodBorder: .red,
                actorFill: .red, actorBorder: .red, actorIcon: .red,
                databaseFill: .red, databaseBorder: .red, databaseIcon: .red,
                artifactFill: .red, artifactBorder: .red, artifactIcon: .red
            ),
            exportTheme: .dark,
            typeColors: { _ in solid }, participantColors: { _ in solid },
            containerColors: { _ in ContainerColors(fill: .red, header: .red, border: .red) }
        )
        #expect(scratch.headerBackground(for: .protocol) == Color.red)
        #expect(scratch.containerFill(.package) == Color.red)
    }
}
