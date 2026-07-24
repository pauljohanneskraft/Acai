import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import AcaiRender

/// Rasterizes a SwiftUI view to PNG for Layer 1 (`TESTING_ARCHITECTURE.md`) screen snapshots, at a
/// fixed size/color scheme. A thin wrapper around `AcaiRender`'s own `DiagramImageRenderer`, so
/// app screens are rasterized through the exact same path diagram image exports already use,
/// rather than a second, parallel `ImageRenderer` setup.
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
/// Duplicated from `ExamplePNGs`' comparison math in trimmed form rather than shared across test
/// targets: it's ~40 lines of pure math and the two test targets aren't set up to share code today.
/// Revisit factoring it out if a third consumer appears (see `TESTING_ARCHITECTURE.md` Layer 1).
struct SnapshotComparator {
    let goldenDirectory: URL
    var maxChangedFraction: Double = 5.0e-5

    private let comparisonSide = 256
    private let perCellDelta = 16

    private func isLFSPointer(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.hasPrefix("version https://git-lfs")
    }

    private func hasPNGMagic(_ data: Data) -> Bool {
        Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]
    }

    private func luminanceGrid(_ data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var buffer = [UInt8](repeating: 0, count: comparisonSide * comparisonSide)
        guard let context = CGContext(
            data: &buffer, width: comparisonSide, height: comparisonSide, bitsPerComponent: 8,
            bytesPerRow: comparisonSide, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Opaque white ground so transparent regions read as background, then draw scaled to fill.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        return buffer
    }

    private func changedCellFraction(_ lhs: Data, _ rhs: Data) -> Double? {
        guard let a = luminanceGrid(lhs), let b = luminanceGrid(rhs) else { return nil }
        let changed = zip(a, b).reduce(0) { abs(Int($1.0) - Int($1.1)) > perCellDelta ? $0 + 1 : $0 }
        return Double(changed) / Double(a.count)
    }

    /// When set (`ACAI_RECORD_SNAPSHOTS=1`), `validate` writes `render()`'s output to the golden
    /// path instead of comparing against it — the deliberate record-mode escape hatch: run once
    /// locally to create/update goldens, review the diff like any other committed file, then run
    /// again without the variable to confirm the comparison itself passes.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_SNAPSHOTS"] == "1"
    }

    /// Validates `render()`'s output against `<goldenDirectory>/<name>.png`. `name` should already
    /// include any color-scheme suffix (e.g. `"newProjectSheet.dark"`).
    @MainActor
    func validate(_ name: String, render: () throws -> Data) throws {
        let url = goldenDirectory.appendingPathComponent("\(name).png")

        if isRecording {
            let rendered = try render()
            try FileManager.default.createDirectory(
                at: goldenDirectory, withIntermediateDirectories: true
            )
            try rendered.write(to: url)
            return
        }

        let committed = try Data(contentsOf: url)
        #expect(!committed.isEmpty, "\(name).png is empty")
        if isLFSPointer(committed) { return }  // LFS not materialized — nothing more to check.
        #expect(hasPNGMagic(committed), "\(name).png is neither a PNG nor an LFS pointer")

        let rendered: Data
        do {
            rendered = try render()
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return  // Headless host: the structural checks above already ran.
        }
        #expect(hasPNGMagic(rendered), "freshly rendered \(name).png is not a PNG")

        guard let changed = changedCellFraction(committed, rendered) else {
            Issue.record("Could not compute perceptual diff for \(name).png")
            return
        }
        let changedCells = Int(changed * Double(comparisonSide * comparisonSide))
        #expect(
            changed <= maxChangedFraction,
            "\(name).png content drifted (\(changedCells) cells); rerecord the golden if intentional"
        )
    }
}
