import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Duplicated from `Tests/AcaiAppTests/ViewSnapshot.swift`'s `SnapshotComparator` rather than
/// shared: this is a standalone Xcode-project target, not SwiftPM, so there's no product boundary
/// to import another test target's internal types through.
///
/// Goldens are only ever recorded on CI (`Scripts/snapshots_accept.sh`): a local renderer does not
/// reproduce CI's bytes, so a local drift is not a signal either way.
@MainActor
struct ScreenshotComparator {
    let goldenDirectory: URL
    /// The fraction of 256×256 luminance cells allowed to differ. A drift above it is a real content
    /// change until proven otherwise: before raising it, look at the capture — every past "noise"
    /// case turned out to be a duplicate row, a stale golden or an unpinned status bar.
    var maxChangedFraction: Double

    init(goldenDirectory: URL, maxChangedFraction: Double? = nil) {
        self.goldenDirectory = goldenDirectory
        self.maxChangedFraction = maxChangedFraction ?? (SnapshotPlatform().name == "macOS" ? 4.0e-2 : 2.0e-3)
    }

    private let comparisonSide = 256
    private let perCellDelta = 16

    /// Where every `validate` call writes its capture — never `goldenDirectory` itself, which stays
    /// read-only. Mirrors its `<platform>/<viewType>/<state>` layout, so CI's uploaded folder drops
    /// straight over the committed goldens. Not `FileManager.default.temporaryDirectory` on macOS:
    /// that resolves inside the sandboxed UI test runner's own container.
    private var outputDirectory: URL {
        #if os(macOS)
        URL(fileURLWithPath: "/private/tmp/AcaiUITestSnapshots", isDirectory: true)
        #else
        goldenDirectory.deletingLastPathComponent().appendingPathComponent("__RecordedSnapshots__", isDirectory: true)
        #endif
    }

    /// Fallback write target for macOS, in case even `outputDirectory`'s entitled `/private/tmp`
    /// write unexpectedly fails. `Scripts/sync_ui_snapshots.sh` copies it into place.
    private var stagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AcaiUITestSnapshots", isDirectory: true)
    }

    private func image(_ data: Data) -> CGImage? {
        guard Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47],
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func luminanceGrid(_ image: CGImage) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: comparisonSide * comparisonSide)
        guard let context = CGContext(
            data: &buffer, width: comparisonSide, height: comparisonSide, bitsPerComponent: 8,
            bytesPerRow: comparisonSide, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        return buffer
    }

    private func changedCellFraction(_ lhs: CGImage, _ rhs: CGImage) -> Double? {
        guard let lhsGrid = luminanceGrid(lhs), let rhsGrid = luminanceGrid(rhs) else { return nil }
        let changed = zip(lhsGrid, rhsGrid).reduce(0) { count, pair in
            abs(Int(pair.0) - Int(pair.1)) > perCellDelta ? count + 1 : count
        }
        return Double(changed) / Double(lhsGrid.count)
    }

    /// Validates `screenshot` against `<goldenDirectory>/<platform>/<viewType>/<state>.png`, returning
    /// a failure message instead of asserting so the caller decides when to report it.
    func validate(
        viewType: String, state: String, screenshot: XCUIScreenshot, testCase: XCTestCase
    ) -> String? {
        let name = "\(SnapshotPlatform().name)/\(viewType)/\(state)"

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name.replacingOccurrences(of: "/", with: "_")
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let rendered = screenshot.pngRepresentation
        guard let committed = try? Data(contentsOf: goldenDirectory.appendingPathComponent("\(name).png")) else {
            write(rendered, name: name)
            return "Missing golden \(name).png — a new screenshot state is red on its first CI run by design; "
                + "accept it with Scripts/snapshots_accept.sh from that run"
        }
        guard let committedImage = image(committed) else { return "\(name).png golden is not a valid PNG" }
        guard let renderedImage = image(rendered) else { return "\(name).png capture is not a valid PNG" }
        guard committedImage.width == renderedImage.width, committedImage.height == renderedImage.height else {
            write(rendered, name: name)
            return "\(name).png golden is \(committedImage.width)×\(committedImage.height) but the capture is "
                + "\(renderedImage.width)×\(renderedImage.height) — re-accept it from CI"
        }
        guard let changed = changedCellFraction(committedImage, renderedImage) else {
            return "Could not compute perceptual diff for \(name).png"
        }

        // Below-threshold drift writes the committed golden's own bytes back, so an unchanged state
        // produces no diff when CI's output is dropped over `__Snapshots__/`.
        write(changed <= maxChangedFraction ? committed : rendered, name: name)

        let changedCells = Int(changed * Double(comparisonSide * comparisonSide))
        // One file per state, read by `Scripts/snapshot_drift_summary.sh` for the CI job summary.
        let drift = String(format: "%@ %.4f %.4f %d", name, changed * 100, maxChangedFraction * 100, changedCells)
        XCTContext.runActivity(named: "drift: \(drift)") { _ in }
        write(Data(drift.utf8), name: name, extension: "drift")
        guard changed <= maxChangedFraction else {
            return String(
                format: "%@.png drifted %.4f%% (%d cells) over its %.4f%% threshold",
                name, changed * 100, changedCells, maxChangedFraction * 100
            )
        }
        return nil
    }

    /// A write failure is logged, not thrown — it shouldn't obscure the drift result itself.
    private func write(_ data: Data, name: String, extension pathExtension: String = "png") {
        let url = outputDirectory.appendingPathComponent("\(name).\(pathExtension)")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        } catch {
            let stagedURL = stagingDirectory.appendingPathComponent("\(name).\(pathExtension)")
            do {
                try FileManager.default.createDirectory(
                    at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: stagedURL)
                XCTContext.runActivity(named:
                    "Could not write snapshot to \(url.path) (\(error)); staged at \(stagedURL.path) instead"
                ) { _ in }
            } catch {
                XCTContext.runActivity(named:
                    "Failed to write snapshot at \(url.path), and the staging fallback also failed: \(error)"
                ) { _ in }
            }
        }
    }
}
