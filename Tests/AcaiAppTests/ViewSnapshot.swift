import CoreGraphics
import Foundation
import SwiftUI
import Testing
import AcaiPNGComparison
import AcaiRender

/// Rasterizes a SwiftUI view to PNG for the render snapshot tests, at a fixed size/color scheme.
/// A thin wrapper around `AcaiRender`'s own `DiagramImageRenderer`, so app screens are rasterized
/// through the exact same path diagram image exports already use.
@MainActor
struct ViewSnapshotRenderer {
    var scale: CGFloat = 2
    private let renderer = DiagramImageRenderer()

    func png(of view: some View, size: CGSize, colorScheme: ColorScheme) throws -> Data {
        let sized = view
            .frame(width: size.width, height: size.height)
            .colorScheme(colorScheme)
        return try renderer.render(sized, contentSize: size, scale: scale, padding: 0)
    }
}

/// Compares a freshly rendered PNG against a golden committed under `__Snapshots__/`, tolerating
/// the same two environment realities `Tests/AcaiRenderTests/TestSupport.swift`'s `ExamplePNGs`
/// already does for `AcaiRender`'s own diagram-image goldens: an unmaterialized Git LFS pointer
/// (`*.png` is LFS-tracked repo-wide per `.gitattributes`), and headless rendering — `ImageRenderer`
/// needs a window-server session, so a rendering failure on a headless host is skipped, not failed.
///
/// A thin wrapper around `AcaiPNGComparison`'s `PNGGoldenComparison`, adding the golden-file lookup
/// and headless-host skip logic this consumer needs on top of the shared perceptual-diff math.
struct SnapshotComparator {
    let goldenDirectory: URL
    var maxChangedFraction: Double = 5.0e-5

    /// Validates `render()`'s output against `<goldenDirectory>/<name>.png`. `name` should already
    /// include any color-scheme suffix (e.g. `"newProjectSheet.dark"`). There is no local recording
    /// mode: create or update a golden by writing `render()`'s PNG output to `url` directly (e.g.
    /// from a scratch script or debugger expression), then review the diff like any other committed
    /// file before running this again to confirm the comparison itself passes.
    @MainActor
    func validate(_ name: String, render: () throws -> Data) throws {
        let url = goldenDirectory.appendingPathComponent("\(name).png")
        let comparison = PNGGoldenComparison(maxChangedFraction: maxChangedFraction)

        let committed = try Data(contentsOf: url)
        #expect(!committed.isEmpty, "\(name).png is empty")
        if comparison.isLFSPointer(committed) { return }  // LFS not materialized — nothing more to check.
        #expect(comparison.hasPNGMagic(committed), "\(name).png is neither a PNG nor an LFS pointer")

        let rendered: Data
        do {
            rendered = try render()
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return  // Headless host: the structural checks above already ran.
        }
        #expect(comparison.hasPNGMagic(rendered), "freshly rendered \(name).png is not a PNG")

        switch comparison.compare(committed: committed, rendered: rendered) {
        case .match, .lfsPointer, .notAPNG:
            break
        case .drifted(let changedCells, _):
            Issue.record("\(name).png content drifted (\(changedCells) cells); rerecord the golden if intentional")
        case .undecodable:
            Issue.record("Could not compute perceptual diff for \(name).png")
        }
    }
}
