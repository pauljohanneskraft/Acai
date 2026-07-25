import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Perceptually diffs an `XCUIScreenshot` against a golden committed under
/// `App/AcaiUITests/__Snapshots__/`.
///
/// Duplicated from `Tests/AcaiAppTests/ViewSnapshot.swift`'s `SnapshotComparator` rather than
/// shared: this is a standalone Xcode-project target, not SwiftPM, so there's no product boundary
/// to import another test target's internal types through.
@MainActor
struct ScreenshotComparator {
    /// iPad journeys capture both device rotations for states that plausibly lay out differently in
    /// each; iPhone and macOS goldens are always a plain `<state>.png`.
    enum Orientation: String {
        case portrait
        case landscape
    }

    let goldenDirectory: URL
    /// Looser than the render snapshot tests' default — a full captured window has real
    /// rendering/anti-aliasing drift. macOS is widened further still: ~2–2.3% drift measured between
    /// separate real-window launches of the same state (window-server font hinting noise a simulator
    /// doesn't have); iOS/iPad showed none of it, so their tighter default stays.
    var maxChangedFraction: Double

    init(goldenDirectory: URL, maxChangedFraction: Double? = nil) {
        self.goldenDirectory = goldenDirectory
        self.maxChangedFraction = maxChangedFraction ?? (SnapshotPlatform().name == "macOS" ? 4.0e-2 : 2.0e-3)
    }

    private let comparisonSide = 256
    private let perCellDelta = 16

    /// When set (`ACAI_RECORD_SNAPSHOTS=1`), `validate` writes the capture to the golden path
    /// instead of comparing — same record-mode convention as the render snapshot tests' `SnapshotComparator`.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_SNAPSHOTS"] == "1"
    }

    /// Fallback recording target for macOS, where the UI test process can fail writing into the
    /// source tree with `EPERM` (the iOS Simulator doesn't have this problem). Mirrors
    /// `goldenDirectory`'s own `<platform>/<viewType>/<state>` layout so `Scripts/sync_ui_snapshots.sh`
    /// can copy it into place with no per-file renaming.
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
        let changed = zip(a, b).reduce(0) { abs(Int($1.0) - Int($1.1)) > perCellDelta ? $0 + 1 : $0 }
        return Double(changed) / Double(a.count)
    }

    /// Validates `screenshot` against `<goldenDirectory>/<platform>/<viewType>/<state>[_<orientation>].png`.
    /// Platform comes first in the path so a CI recording job can upload just its own platform's
    /// subtree as a self-contained artifact. Regardless of pass/fail/record, attaches the screenshot
    /// to `testCase` (`.keepAlways`) so it's reviewable in the test report — this layer doubles as a
    /// human-reviewable screenshot journey, not only an automated regression check.
    /// `maxChangedFraction` is a per-call override (not per-instance) since one comparator is
    /// typically reused across a whole journey and only a state or two needs a looser bound (e.g. a
    /// `Menu`'s translucent material doesn't render byte-identically across separate app launches).
    func validate(
        viewType: String, state: String, orientation: Orientation? = nil,
        screenshot: XCUIScreenshot, testCase: XCTestCase, maxChangedFraction overrideMaxChangedFraction: Double? = nil
    ) {
        var fileName = state
        if let orientation { fileName += "_\(orientation.rawValue)" }
        let name = "\(SnapshotPlatform().name)/\(viewType)/\(fileName)"

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name.replacingOccurrences(of: "/", with: "_")
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let url = goldenDirectory.appendingPathComponent("\(name).png")
        let rendered = screenshot.pngRepresentation

        if isRecording {
            record(rendered, name: name, to: url)
            return
        }

        guard let committed = try? Data(contentsOf: url) else {
            XCTFail("Missing golden \(name).png — run once with ACAI_RECORD_SNAPSHOTS=1 to record it")
            return
        }
        guard hasPNGMagic(committed), hasPNGMagic(rendered) else {
            XCTFail("\(name).png golden or fresh capture is not a valid PNG")
            return
        }
        guard let changed = changedCellFraction(committed, rendered) else {
            XCTFail("Could not compute perceptual diff for \(name).png")
            return
        }
        let changedCells = Int(changed * Double(comparisonSide * comparisonSide))
        let threshold = overrideMaxChangedFraction ?? maxChangedFraction
        // Logged unconditionally (pass or fail) so `maxChangedFraction` can be tightened from real
        // measured noise floors across a run instead of trial-and-error — grep the console/activity
        // log for "drift:" after a run to see every state's actual fraction.
        XCTContext.runActivity(named: String(
            format: "drift: %@ = %.4f%% (%d/%d cells, threshold %.4f%%)",
            name, changed * 100, changedCells, comparisonSide * comparisonSide, threshold * 100
        )) { _ in }
        XCTAssertLessThanOrEqual(
            changed, threshold, "\(name).png content drifted (\(changedCells) cells)"
        )
    }

    /// The `ACAI_RECORD_SNAPSHOTS=1` half of `validate` — writes `rendered` to `url`, falling back
    /// to `stagingDirectory` (see its own doc comment) if the source tree write fails.
    private func record(_ rendered: Data, name: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try rendered.write(to: url)
        } catch {
            let stagedURL = stagingDirectory.appendingPathComponent("\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try rendered.write(to: stagedURL)
                XCTFail(
                    "Could not write golden directly (\(error)); staged at \(stagedURL.path) instead — "
                    + "run Scripts/sync_ui_snapshots.sh to copy staged recordings into __Snapshots__/"
                )
            } catch {
                XCTFail("Failed to record golden at \(url.path), and the staging fallback also failed: \(error)")
            }
        }
    }
}
