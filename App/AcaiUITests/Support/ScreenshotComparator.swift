import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// The Layer 2 screenshot regression mechanism (`TESTING_ARCHITECTURE.md`): perceptually diffs an
/// `XCUIScreenshot` against a golden committed under `App/AcaiUITests/__Snapshots__/`.
///
/// Duplicated from `Tests/AcaiAppTests/ViewSnapshot.swift`'s `SnapshotComparator` (itself
/// duplicated from `Tests/AcaiRenderTests`' `ExamplePNGs`) rather than shared: this is a
/// standalone Xcode-project UI test target, not a SwiftPM target, so there's no product boundary
/// through which to import another test target's internal types. Revisit if a fourth consumer
/// appears — see `TESTING_ARCHITECTURE.md` Layer 1's own note on the same tradeoff.
struct ScreenshotComparator {
    /// An iPad journey capturing both device rotations for a state that plausibly lays out
    /// differently in each. iPhone and macOS goldens never pass this — they get a plain
    /// `<state>.png`.
    enum Orientation: String {
        case portrait
        case landscape
    }

    let goldenDirectory: URL
    /// Looser than Layer 1's default — simulator rendering/anti-aliasing drift is real for a full
    /// captured window, not a single flat component. Looser again on macOS specifically: measured
    /// ~2–2.3% drift between separate real-window launches of the identical state (font
    /// hinting/anti-aliasing noise a window server introduces that a simulator doesn't) — iOS/iPad
    /// showed none of this across repeated runs, so only macOS's default is widened, keeping
    /// iOS/iPad's regression sensitivity tight.
    var maxChangedFraction: Double

    init(goldenDirectory: URL, maxChangedFraction: Double? = nil) {
        self.goldenDirectory = goldenDirectory
        self.maxChangedFraction = maxChangedFraction ?? (SnapshotPlatform().name == "macOS" ? 4.0e-2 : 2.0e-3)
    }

    private let comparisonSide = 256
    private let perCellDelta = 16

    /// When set (`ACAI_RECORD_SNAPSHOTS=1`), `validate` writes the capture to the golden path
    /// instead of comparing — same record-mode convention as Layer 1's `SnapshotComparator`.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_SNAPSHOTS"] == "1"
    }

    /// Fallback recording target, mirroring `goldenDirectory`'s own `<viewType>/<platform>/<state>`
    /// layout so `Scripts/sync_ui_snapshots.sh` can copy it into place with no per-file renaming.
    /// Needed because a real macOS-hosted UI test process (unlike the iOS Simulator, which writes
    /// directly to `goldenDirectory` fine) has been observed to fail writing into the source tree
    /// with `EPERM`, for reasons that didn't resolve even after granting Full Disk Access — the
    /// cause wasn't fully root-caused, so this fallback keeps recording usable regardless of it.
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

    /// Validates `screenshot` against
    /// `<goldenDirectory>/<viewType>/<platform>/<state>[_<orientation>].png` (platform resolved at
    /// runtime via `SnapshotPlatform`, so callers can never forget or misspell it), and —
    /// regardless of pass/fail/record — attaches it to `testCase` (`.keepAlways`) so it's
    /// reviewable in the test report, which is what makes this layer double as a
    /// human-reviewable screenshot journey and not only an automated regression check.
    func validate(
        viewType: String, state: String, orientation: Orientation? = nil,
        screenshot: XCUIScreenshot, testCase: XCTestCase
    ) {
        var fileName = state
        if let orientation { fileName += "_\(orientation.rawValue)" }
        let name = "\(viewType)/\(SnapshotPlatform().name)/\(fileName)"

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name.replacingOccurrences(of: "/", with: "_")
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let url = goldenDirectory.appendingPathComponent("\(name).png")
        let rendered = screenshot.pngRepresentation

        if isRecording {
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
        XCTAssertLessThanOrEqual(
            changed, maxChangedFraction, "\(name).png content drifted (\(changedCells) cells)"
        )
    }
}
