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
    let goldenDirectory: URL
    /// Looser than Layer 1's default — simulator rendering/anti-aliasing drift is real for a full
    /// captured window, not a single flat component.
    var maxChangedFraction: Double = 2.0e-3

    private let comparisonSide = 256
    private let perCellDelta = 16

    /// When set (`ACAI_RECORD_SNAPSHOTS=1`), `validate` writes the capture to the golden path
    /// instead of comparing — same record-mode convention as Layer 1's `SnapshotComparator`.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["ACAI_RECORD_SNAPSHOTS"] == "1"
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

    /// Validates `screenshot` against `<goldenDirectory>/<name>.png`, and — regardless of
    /// pass/fail/record — attaches it to `testCase` (`.keepAlways`) so it's reviewable in the test
    /// report, which is what makes this layer double as a human-reviewable screenshot journey and
    /// not only an automated regression check.
    func validate(_ name: String, screenshot: XCUIScreenshot, testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let url = goldenDirectory.appendingPathComponent("\(name).png")
        let rendered = screenshot.pngRepresentation

        if isRecording {
            try? FileManager.default.createDirectory(at: goldenDirectory, withIntermediateDirectories: true)
            try? rendered.write(to: url)
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
