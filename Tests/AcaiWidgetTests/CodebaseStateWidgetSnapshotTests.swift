#if os(iOS)
import Foundation
import SwiftUI
import Testing
import UIKit
import WidgetKit
import AcaiPNGComparison
@testable import AcaiAppModel
@testable import AcaiWidget

/// iOS only: the Xcode-built package tests are the one CI run that compiles the widget's `.xcstrings`.
@Suite("Widget render snapshots", .timeLimit(.minutes(1)))
struct CodebaseStateWidgetSnapshotTests {
    struct Variant: Sendable, CustomTestStringConvertible {
        let name: String
        let state: CodebaseWidgetPresentation.State

        var testDescription: String { name }
    }

    struct Layout: Sendable, CustomTestStringConvertible {
        let name: String
        let isCompact: Bool
        let size: CGSize
        let isDark: Bool

        var testDescription: String { "\(name)\(isDark ? ".dark" : "")" }
    }

    static let variants: [Variant] = {
        let now = Date()
        let analysed = CodebaseWidgetSnapshot(
            codebaseID: UUID(), codebaseName: "Açaí", analysedAt: now.addingTimeInterval(-2 * 60 * 60 - 60),
            analysedRevision: "9f3c2a1b", freshnessCheckedAt: now.addingTimeInterval(-60 * 60 - 60),
            typeCount: 128, findingCount: 4, criticalFindingCount: 1)
        var outOfDate = analysed
        outOfDate.isOutOfDate = true
        outOfDate.hasParseErrors = true
        var notChecked = analysed
        notChecked.freshnessCheckedAt = nil
        var countsPending = analysed
        countsPending.typeCount = nil
        countsPending.findingCount = nil
        countsPending.criticalFindingCount = nil
        return [
            Variant(name: "nothingShared", state: .nothingShared),
            Variant(name: "codebaseMissing", state: .codebaseMissing),
            Variant(name: "notAnalysed", state: .notAnalysed(CodebaseWidgetSnapshot(
                codebaseID: UUID(), codebaseName: "Açaí"))),
            Variant(name: "upToDate", state: .analysed(analysed)),
            Variant(name: "outOfDate", state: .analysed(outOfDate)),
            Variant(name: "changesNotChecked", state: .analysed(notChecked)),
            Variant(name: "countsNotComputed", state: .analysed(countsPending))
        ]
    }()

    static let layouts: [Layout] = [false, true].flatMap { isDark in
        [
            Layout(name: "small", isCompact: true, size: CGSize(width: 170, height: 170), isDark: isDark),
            Layout(name: "medium", isCompact: false, size: CGSize(width: 364, height: 170), isDark: isDark)
        ]
    }

    private let snapshots = WidgetSnapshotFiles(
        testsDirectory: URL(fileURLWithPath: #filePath).deletingLastPathComponent())

    @Test("The widget's strings resolve here, so no golden can capture raw identifiers")
    func stringsResolve() {
        let key = "Widget.CodebaseState.DisplayName"
        #expect(String(localized: .widget(String.LocalizationValue(key))) != key)
    }

    @Test("Each widget state at each size, light and dark", arguments: variants, layouts)
    @MainActor func widgetState(_ variant: Variant, _ layout: Layout) throws {
        let scheme: ColorScheme = layout.isDark ? .dark : .light
        let view = CodebaseStateContentView(state: variant.state, isCompact: layout.isCompact)
            .padding(16)
            .frame(width: layout.size.width, height: layout.size.height)
            .background(Color(uiColor: .secondarySystemBackground))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let png = try #require(renderer.uiImage?.pngData(), "ImageRenderer produced no image")
        try snapshots.validate(png, name: "\(variant.name).\(layout.testDescription)")
    }
}

/// Every render lands in `__RecordedSnapshots__` first, so a missing or drifted golden still leaves one to accept.
struct WidgetSnapshotFiles {
    let testsDirectory: URL
    var comparison = PNGGoldenComparison()

    var goldens: URL { testsDirectory.appendingPathComponent("__Snapshots__") }
    var recordings: URL { testsDirectory.appendingPathComponent("__RecordedSnapshots__") }

    func validate(_ rendered: Data, name: String) throws {
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        try rendered.write(to: recordings.appendingPathComponent("\(name).png"))
        guard let golden = try? Data(contentsOf: goldens.appendingPathComponent("\(name).png")) else {
            Issue.record("\(name).png has no golden; accept CI's capture with Scripts/snapshots_accept.sh")
            return
        }
        switch comparison.compare(committed: golden, rendered: rendered) {
        case .match:
            try recordDrift(name: name, changedCells: 0, totalCells: 1)
        case .drifted(let changedCells, let totalCells):
            try recordDrift(name: name, changedCells: changedCells, totalCells: totalCells)
            Issue.record("\(name).png drifted (\(changedCells) of \(totalCells) cells)")
        case .lfsPointer, .notAPNG, .undecodable:
            Issue.record("\(name).png's golden is not a readable PNG")
        }
    }

    private func recordDrift(name: String, changedCells: Int, totalCells: Int) throws {
        let percent = Double(changedCells) / Double(totalCells) * 100
        let line = String(
            format: "%@ %.4f %.4f %d", name, percent, comparison.maxChangedFraction * 100, changedCells)
        try Data(line.utf8).write(to: recordings.appendingPathComponent("\(name).drift"))
    }
}
#endif
