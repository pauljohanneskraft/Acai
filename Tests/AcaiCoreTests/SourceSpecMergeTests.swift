import Foundation
import Testing
@testable import AcaiCore

/// Several roots of one language reach enrichment as a single spec, so what merging does with each
/// `SourceSpec` field is behaviour a later field has to decide too.
@Suite("SourceSpec merging")
struct SourceSpecMergeTests {

    private func spec(_ name: String, dirs: [String], diagnostics: [ParseDiagnostic] = []) -> SourceSpec {
        let root = URL(fileURLWithPath: "/repo/\(name)", isDirectory: true)
        return SourceSpec(
            language: .swift,
            sourceDirs: dirs.map { root.appendingPathComponent($0, isDirectory: true) },
            root: root,
            detector: "Detector\(name)",
            diagnostics: diagnostics
        )
    }

    @Test func mergingAccumulatesSourceDirsAndKeepsTheFirstRoot() {
        let merged = spec("one", dirs: ["Sources"]).merging(spec("two", dirs: ["Sources", "Plugins"]))

        #expect(merged.language == .swift)
        #expect(merged.sourceDirs.map(\.lastPathComponent) == ["Sources", "Sources", "Plugins"])
        #expect(merged.root.lastPathComponent == "one")
        #expect(merged.detector == "Detectorone")
    }

    /// A problem found discovering the second root must survive the merge alongside the first root's
    /// own — neither silently dropped nor overwritten.
    @Test func mergingConcatenatesDiagnosticsFromBothRoots() {
        let oneDiagnostic = ParseDiagnostic(
            location: SourceLocation(filePath: "/repo/one/a.swift", line: 1, column: 1),
            kind: .missing,
            message: "one's problem"
        )
        let twoDiagnostic = ParseDiagnostic(
            location: SourceLocation(filePath: "/repo/two/b.swift", line: 2, column: 1),
            kind: .missing,
            message: "two's problem"
        )
        let merged = spec("one", dirs: ["Sources"], diagnostics: [oneDiagnostic])
            .merging(spec("two", dirs: ["Sources"], diagnostics: [twoDiagnostic]))

        #expect(merged.diagnostics == [oneDiagnostic, twoDiagnostic])
    }

    @Test func mergingConcatenatesNestedRootPaths() {
        var one = spec("one", dirs: ["."])
        one.nestedRootPaths = [URL(fileURLWithPath: "/repo/one/core")]
        var two = spec("two", dirs: ["."])
        two.nestedRootPaths = [URL(fileURLWithPath: "/repo/two/ui")]

        #expect(one.merging(two).nestedRootPaths.map(\.lastPathComponent) == ["core", "ui"])
    }

    /// `isFallback` describes how one root was found, so a merged spec keeps the first root's rather
    /// than implying the whole language was guessed. The per-root truth is in
    /// `metadata.discoveredRoots`, which is built before merging.
    @Test func mergingKeepsTheFirstRootsFallbackFlag() {
        var guessed = spec("guessed", dirs: ["."])
        guessed.isFallback = true
        let claimed = spec("claimed", dirs: ["Sources"])

        #expect(claimed.merging(guessed).isFallback == false)
        #expect(guessed.merging(claimed).isFallback)
    }

    @Test func mergedByLanguageFoldsOnlyWithinALanguage() {
        let kotlin = SourceSpec(
            language: .kotlin,
            sourceDirs: [URL(fileURLWithPath: "/repo/android/src", isDirectory: true)],
            root: URL(fileURLWithPath: "/repo/android", isDirectory: true),
            detector: "Gradle"
        )
        let merged = [spec("one", dirs: ["Sources"]), kotlin, spec("two", dirs: ["Sources"])]
            .mergedByLanguage

        #expect(merged.map(\.language) == [.swift, .kotlin])
        #expect(merged[0].sourceDirs.count == 2)
        #expect(merged[1].sourceDirs.count == 1)
    }
}
