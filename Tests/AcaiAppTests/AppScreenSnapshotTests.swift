import Foundation
import SwiftUI
import Testing
import AcaiCore
import AcaiRender
@testable import AcaiApp

/// Render snapshot tests: perceptually diff a real `AcaiApp` view against a committed golden,
/// light and dark.
///
/// **Scoped to flat, self-contained freeform node views only** — not full interactive screens.
/// `ImageRenderer`'s single off-screen pass has no real window server, so it can't resolve
/// AppKit-backed controls, vibrancy/material effects, or a live measurement→layout feedback loop
/// (`onPreferenceChange`/`GeometryReader`) — it renders blank canvases or diagnostic "unavailable"
/// glyphs for anything that depends on those. `AcaiApp`'s freeform node views below are flat,
/// pre-laid-out, materials-free content, so they render cleanly; real interactive screens are
/// covered by the snapshot tests (XCUITest) instead.
@Suite("App screen snapshots")
struct AppScreenSnapshotTests {

    private static let goldenDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")

    private static let comparator = SnapshotComparator(goldenDirectory: goldenDirectory)
    private static let nodeSize = CGSize(width: 220, height: 120)

    typealias Theme = (suffix: String, palette: DiagramPalette, scheme: ColorScheme)

    /// Both `DiagramPalette`s a golden is checked against — `diagramPalette`'s environment default
    /// is always `.light` (`DiagramPalette+Environment.swift`), so dark must be injected
    /// explicitly, the same way `ExamplePNGs.themes` feeds `RenderingContext(palette:)` explicitly
    /// rather than relying on `.colorScheme()` alone.
    private static let themes: [Theme] = [
        ("", .light, .light),
        (".dark", .dark, .dark)
    ]

    @MainActor
    private func render(_ view: some View, theme: Theme, size: CGSize = Self.nodeSize) throws -> Data {
        let themed = view
            .environment(\.diagramPalette, theme.palette)
            .colorScheme(theme.scheme)
        return try ViewSnapshotRenderer().png(of: themed, size: size, colorScheme: theme.scheme)
    }

    @Test("Freeform note node", arguments: themes)
    @MainActor func noteNode(_ theme: Theme) throws {
        let view = NoteNodeView(name: "Reminder", text: "Check this before shipping.", isSelected: false)
        try Self.comparator.validate("freeformNoteNode\(theme.suffix)") { try render(view, theme: theme) }
    }

    @Test("Freeform stereotyped box node", arguments: themes)
    @MainActor func stereotypedBoxNode(_ theme: Theme) throws {
        let view = StereotypedBoxNodeView(
            name: "AuthService", stereotype: "service", systemImage: "shippingbox", isSelected: false
        )
        try Self.comparator.validate("freeformStereotypedBoxNode\(theme.suffix)") { try render(view, theme: theme) }
    }

    @Test("Freeform use case node", arguments: themes)
    @MainActor func useCaseNode(_ theme: Theme) throws {
        let view = UseCaseNodeView(name: "Place Order", isSelected: false)
        try Self.comparator.validate("freeformUseCaseNode\(theme.suffix)") { try render(view, theme: theme) }
    }

    /// A converted-from-Class-Diagram `.type` node carries its manual resize into `node.width`/
    /// `.height` (B20's fix — `GeneratedDiagram.buildFreeformNodes`), and
    /// `FreeformDiagramView.nodeContent`'s middle branch re-applies it as an explicit `.frame`
    /// instead of letting the box revert to auto-measured content size. This snapshots that exact
    /// composition (`TypeNodeView` + an explicit outer `.frame`) at a deliberately elongated size
    /// no auto-measured type box would ever naturally take, so a regression back to auto-sizing
    /// would visibly change the golden.
    @Test("Freeform type node honors an explicit stored size", arguments: themes)
    @MainActor func typeNodeExplicitSize(_ theme: Theme) throws {
        let explicitSize = CGSize(width: 340, height: 90)
        let node = FreeformDiagram.Node(
            name: "WideRecord",
            content: .type(.init(
                typeKind: .class,
                properties: [.init(name: "id", type: "String")],
                methods: []
            ))
        )
        guard case .type(let content) = node.content else { return }
        let view = TypeNodeView(node: node, content: content, isSelected: false)
            .frame(width: explicitSize.width, height: explicitSize.height)
        try Self.comparator.validate("freeformTypeNodeExplicitSize\(theme.suffix)") {
            try render(view, theme: theme, size: explicitSize)
        }
    }
}
