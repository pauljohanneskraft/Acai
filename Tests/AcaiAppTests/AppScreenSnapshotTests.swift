import Foundation
import SwiftUI
import Testing
import AcaiRender
@testable import AcaiApp

/// Layer 1 view snapshots (`TESTING_ARCHITECTURE.md`): perceptually diff a real `AcaiApp` view
/// against a committed golden, light and dark.
///
/// **Scoped to flat, self-contained freeform node views only** — not full interactive screens.
/// An earlier version of this suite snapshotted `ProjectDetailView`/`NewProjectSheet`/
/// `ClassDiagramView` directly and produced garbage (blank canvases, AppKit's diagnostic
/// yellow/red "unavailable" glyph in place of `TextField`/material backgrounds) — `ImageRenderer`'s
/// single off-screen pass has no real window server, so it can't resolve AppKit-backed controls,
/// vibrancy/material effects, or (for `ClassDiagramView` specifically) the live
/// measurement→layout feedback loop (`onPreferenceChange`/`GeometryReader`) those screens depend
/// on. `AcaiRender`'s own diagram views (`TypeNodeView`, `StateNodeView`, tested in
/// `Tests/AcaiRenderTests`) render cleanly because they're purpose-built as flat, pre-laid-out,
/// materials-free snapshot content — and so are `AcaiApp`'s own freeform node views below, which
/// `AcaiRenderTests` doesn't cover (it only exercises the generated-diagram node views). Real
/// interactive screens are covered by Layer 2 (XCUITest) screenshots instead — see
/// `TESTING_ARCHITECTURE.md`.
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
    /// rather than relying on `.colorScheme()` alone. Guardrails §9's "verified dark-appearance
    /// value" rule.
    private static let themes: [Theme] = [
        ("", .light, .light),
        (".dark", .dark, .dark)
    ]

    @MainActor
    private func render(_ view: some View, theme: Theme) throws -> Data {
        let themed = view
            .environment(\.diagramPalette, theme.palette)
            .colorScheme(theme.scheme)
        return try ViewSnapshotRenderer().png(of: themed, size: Self.nodeSize, colorScheme: theme.scheme)
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
}
