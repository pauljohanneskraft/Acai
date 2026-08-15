import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("CompareFindingsDelta")
struct CompareFindingsDeltaTests {
    private func finding(
        id: String, title: String, filePath: String, line: Int, offsetInID: Int = 0
    ) -> Finding {
        Finding(
            id: "\(id)-\(offsetInID)",
            kind: .violation,
            severity: .warning,
            codebaseID: UUID(),
            codebaseName: "App",
            title: title,
            message: "message",
            location: SourceLocation(filePath: filePath, line: line, column: 1),
            reference: nil,
            indexedAt: nil)
    }

    @Test func genuinelyNewFindingIsSurfaced() {
        let old = [finding(id: "a", title: "Long function", filePath: "Foo.swift", line: 10)]
        let new = old + [finding(id: "b", title: "God class", filePath: "Bar.swift", line: 3)]

        let delta = CompareFindingsDelta(oldFindings: old, newFindings: new)

        #expect(delta.added.map(\.title) == ["God class"])
    }

    @Test func sameFindingShiftedToADifferentLineIsNotReportedAsNew() {
        // Same rule/subject/file, but the flagged line moved because unrelated code was added
        // earlier in the file — `Finding.id` (which embeds an array offset) would differ, but the
        // delta should still recognize this as the same finding.
        let old = [finding(id: "long-function-Foo", title: "Long function", filePath: "Foo.swift", line: 10)]
        let new = [finding(id: "long-function-Foo", title: "Long function", filePath: "Foo.swift", line: 25)]

        let delta = CompareFindingsDelta(oldFindings: old, newFindings: new)

        #expect(delta.added.isEmpty)
    }

    @Test func findingWithSameTitleInADifferentFileIsReportedAsNew() {
        let old = [finding(id: "a", title: "Long function", filePath: "Foo.swift", line: 10)]
        let new = [finding(id: "a", title: "Long function", filePath: "Baz.swift", line: 10)]

        let delta = CompareFindingsDelta(oldFindings: old, newFindings: new)

        #expect(delta.added.map(\.title) == ["Long function"])
    }

    @Test func resolvedFindingIsNotReportedAsNew() {
        let old = [finding(id: "a", title: "Long function", filePath: "Foo.swift", line: 10)]
        let new: [Finding] = []

        let delta = CompareFindingsDelta(oldFindings: old, newFindings: new)

        #expect(delta.added.isEmpty)
    }
}
