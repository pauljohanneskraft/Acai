import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// Regression coverage for a reported bug: analyzing a real multi-target Swift package produced
/// per-module statistics ("Instability", "Abstractness", …) that collapsed every type into a single
/// fake `"root"` module instead of the package's real targets. `ModuleResolver.productName` only
/// falls back to `"root"` when a type's `location.filePath` has one path component or fewer — so
/// this pins down whether `AnalysisService.standard.analyzeProject`, run end-to-end through the real
/// Swift parser and `ProjectDiscovery`, still resolves each target's files to a proper module name.
@Suite("Module metrics regression")
struct ModuleMetricsRegressionTests {

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("acai-module-metrics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func write(_ relativePath: String, in root: URL, contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("a two-target SPM layout resolves to two real modules, not a single \"root\"")
    func multiTargetLayoutResolvesRealModules() throws {
        try withTempDir { root in
            try write("Package.swift", in: root, contents: "// swift-tools-version:5.9")
            try write("Sources/A/X.swift", in: root, contents: "class X {}")
            try write("Sources/B/Y.swift", in: root, contents: "class Y {}")

            let artifact = try AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])
            let metrics = artifact.computeMetrics()

            #expect(Set(metrics.modules.map(\.name)) == ["A", "B"])
            #expect(!metrics.modules.contains { $0.name == ModuleResolver.standard.fallbackGroup })
        }
    }

    /// Exercises the same layout through a base directory that round-trips through the `/private`
    /// symlink macOS temp/sandbox paths commonly go through (`NSTemporaryDirectory()` is itself such
    /// a symlink) — both as the un-resolved value the app typically stores/reconstructs and as the
    /// fully-resolved value `URL(resolvingBookmarkData:...)`-style APIs typically return — to check
    /// `AnalysisService`'s path handling doesn't depend on both sides agreeing on which form is used.
    @Test("module resolution survives a resolved-vs-unresolved root URL mismatch")
    func multiTargetLayoutResolvesWithSymlinkedRoot() throws {
        try withTempDir { unresolvedRoot in
            try write("Package.swift", in: unresolvedRoot, contents: "// swift-tools-version:5.9")
            try write("Sources/A/X.swift", in: unresolvedRoot, contents: "class X {}")
            try write("Sources/B/Y.swift", in: unresolvedRoot, contents: "class Y {}")

            let resolvedRoot = unresolvedRoot.resolvingSymlinksInPath()
            // Only meaningful when NSTemporaryDirectory() actually is a symlink on this machine.
            guard resolvedRoot.path != unresolvedRoot.path else { return }

            let artifact = try AnalysisService.standard.analyzeProject(at: resolvedRoot, allowedLanguages: [])
            let metrics = artifact.computeMetrics()

            #expect(Set(metrics.modules.map(\.name)) == ["A", "B"])
            #expect(!metrics.modules.contains { $0.name == ModuleResolver.standard.fallbackGroup })
        }
    }
}
