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
        #expect(DiagramPalette.light.canvasBackground != DiagramPalette.dark.canvasBackground)
    }

    @Test func forSchemeSelectsBundledTheme() {
        #expect(DiagramPalette.forScheme(.dark).canvasBackground == DiagramPalette.dark.canvasBackground)
        #expect(DiagramPalette.forScheme(.light).canvasBackground == DiagramPalette.light.canvasBackground)
    }

    /// A third party can theme the diagrams without modifying the library: copy-and-tweak a
    /// bundled palette, or construct one from scratch through the public initializer.
    @Test func paletteIsConsumerExtensible() {
        var tweaked = DiagramPalette.light
        tweaked.canvasBackground = .black
        #expect(tweaked.canvasBackground == Color.black)

        let solid = KindColors(header: .red, body: .red, border: .red, accent: .red)
        let scratch = DiagramPalette(
            canvasBackground: .black, primaryInk: .white, secondaryInk: .white, mutedInk: .gray,
            edgeLine: .white, edgeDecorationFill: .black, edgeLabelInk: .white,
            neutralBorder: .gray, subtleSurface: .black, stateBackground: .red,
            choiceBackground: .red, stateSolidFill: .white, callGraphInScopeFill: .red,
            callGraphOutOfScopeFill: .black, useCaseFill: .red, useCaseBorder: .red,
            noteFill: .red, noteBorder: .red, methodFill: .red, methodBorder: .red,
            actorFill: .red, actorBorder: .red, actorIcon: .red, databaseFill: .red,
            databaseBorder: .red, databaseIcon: .red, artifactFill: .red, artifactBorder: .red,
            artifactIcon: .red, exportTheme: .dark,
            typeColors: { _ in solid }, participantColors: { _ in solid },
            containerColors: { _ in ContainerColors(fill: .red, header: .red, border: .red) }
        )
        #expect(scratch.headerBackground(for: .protocol) == Color.red)
        #expect(scratch.containerFill(.package) == Color.red)
    }
}
