import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Duplicated from `Tests/AcaiAppTests/ViewSnapshot.swift`'s `SnapshotComparator` rather than
/// shared: this is a standalone Xcode-project target, not SwiftPM, so there's no product boundary
/// to import another test target's internal types through.
@MainActor
struct ScreenshotComparator {
    /// iPad journeys capture both rotations for states that plausibly lay out differently in each;
    /// iPhone and macOS goldens are always a plain `<state>.png`.
    enum Orientation: String {
        case portrait
        case landscape
    }

    let goldenDirectory: URL
    /// Looser than the render snapshot tests' default — a full captured window has real
    /// rendering/anti-aliasing drift. macOS is widened further still: ~2–2.3% drift measured between
    /// separate real-window launches of the same state (window-server font hinting noise a
    /// simulator doesn't have); iOS/iPad showed none of it.
    var maxChangedFraction: Double

    init(goldenDirectory: URL, maxChangedFraction: Double? = nil) {
        self.goldenDirectory = goldenDirectory
        self.maxChangedFraction = maxChangedFraction ?? (SnapshotPlatform().name == "macOS" ? 4.0e-2 : 2.0e-3)
    }

    private let comparisonSide = 256
    private let perCellDelta = 16
    /// Top rows of the 256×256 grid to always treat as matching, on iOS/iPad only.
    /// `simulator_prepare.sh` pins the status bar via `simctl status_bar override` so goldens don't
    /// churn on the wall clock/battery, but that override has been observed to intermittently not
    /// land on whichever simulator a given CI run tests against — masking the band makes that miss
    /// harmless instead of chasing its root cause. macOS has no status bar, so it stays unmasked.
    private let statusBarMaskRows = 12

    /// Where every `validate` call writes its capture — never `goldenDirectory` itself, which stays
    /// read-only. Mirrors its `<platform>/<viewType>/<state>` layout, so a human can review/copy
    /// the output over the committed goldens with no per-file renaming. There's no local "record
    /// mode" (unlike the render snapshot tests' `SnapshotComparator`): every run already leaves a
    /// ready-to-drop-in folder behind, since a local renderer won't reliably match CI's
    /// bit-for-bit anyway. Not `FileManager.default.temporaryDirectory` on macOS: that resolves
    /// inside the sandboxed UI test runner's own container (see `Launch.swift`'s identical
    /// reasoning). iOS's simulator has no such restriction, so it uses a plain sibling of
    /// `goldenDirectory` instead.
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
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: comparisonSide, height: comparisonSide))
        return buffer
    }

    private func changedCellFraction(_ lhs: Data, _ rhs: Data) -> Double? {
        guard let a = luminanceGrid(lhs), let b = luminanceGrid(rhs) else { return nil }
        let maskedRows = SnapshotPlatform().name == "macOS" ? 0 : statusBarMaskRows
        let changed = zip(a, b).enumerated().reduce(0) { count, indexed in
            let (index, pair) = indexed
            guard index / comparisonSide >= maskedRows else { return count }
            return abs(Int(pair.0) - Int(pair.1)) > perCellDelta ? count + 1 : count
        }
        return Double(changed) / Double(a.count)
    }

    /// Validates `screenshot` against `<goldenDirectory>/<platform>/<viewType>/<state>[_<orientation>].png`.
    /// `maxChangedFraction` is a per-call override (not per-instance) since one comparator is
    /// typically reused across a whole journey and only a state or two needs a looser bound (e.g.
    /// a `Menu`'s translucent material doesn't render byte-identically across separate launches).
    func validate(
        viewType: String, state: String, orientation: Orientation? = nil,
        screenshot: XCUIScreenshot, testCase: XCTestCase, maxChangedFraction overrideMaxChangedFraction: Double? = nil
    ) {
        var fileName = state
        if let orientation { fileName += "_\(orientation.rawValue)" }
        let name = "\(SnapshotPlatform().name)/\(viewType)/\(fileName)"
        let threshold = overrideMaxChangedFraction ?? maxChangedFraction

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name.replacingOccurrences(of: "/", with: "_")
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let url = goldenDirectory.appendingPathComponent("\(name).png")
        let rendered = screenshot.pngRepresentation

        // No golden yet — write the fresh capture as-is so it's still in the uploaded folder.
        guard let committed = try? Data(contentsOf: url) else {
            write(rendered, name: name)
            XCTFail(
                "Missing golden \(name).png — download this platform's screenshot artifact from a "
                + "failed CI run and copy it into App/AcaiUITests/__Snapshots__/"
            )
            return
        }
        guard hasPNGMagic(committed) else {
            XCTFail("\(name).png golden is not a valid PNG")
            return
        }
        guard hasPNGMagic(rendered) else {
            XCTFail("\(name).png fresh capture is not a valid PNG")
            return
        }
        guard let changed = changedCellFraction(committed, rendered) else {
            XCTFail("Could not compute perceptual diff for \(name).png")
            return
        }

        // Below-threshold drift writes the committed golden's own bytes back, so an unchanged state
        // produces no diff for a human dropping the output over `__Snapshots__/`.
        write(changed <= threshold ? committed : rendered, name: name)

        let changedCells = Int(changed * Double(comparisonSide * comparisonSide))
        // Logged unconditionally (pass or fail) — grep the console/activity log for "drift:" to see
        // every state's actual fraction, for tightening `maxChangedFraction` from real measurements.
        XCTContext.runActivity(named: String(
            format: "drift: %@ = %.4f%% (%d/%d cells, threshold %.4f%%)",
            name, changed * 100, changedCells, comparisonSide * comparisonSide, threshold * 100
        )) { _ in }
        XCTAssertLessThanOrEqual(
            changed, threshold, "\(name).png content drifted (\(changedCells) cells)"
        )
    }

    /// Falls back to `stagingDirectory` if the `outputDirectory` write unexpectedly fails. A write
    /// failure is logged, not thrown — an unrelated write hiccup shouldn't obscure the real drift
    /// assertion in `validate`.
    private func write(_ data: Data, name: String) {
        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        } catch {
            let stagedURL = stagingDirectory.appendingPathComponent("\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: stagedURL)
                XCTContext.runActivity(named:
                    "Could not write snapshot to \(url.path) (\(error)); staged at "
                    + "\(stagedURL.path) instead — run Scripts/sync_ui_snapshots.sh to copy staged "
                    + "snapshots into \(outputDirectory.path)/"
                ) { _ in }
            } catch {
                XCTContext.runActivity(named:
                    "Failed to write snapshot at \(url.path), and the staging fallback also failed: \(error)"
                ) { _ in }
            }
        }
    }
}
