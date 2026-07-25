import Foundation
import Testing
import AcaiCore
import AcaiLibrary

/// A real multi-target Swift package must resolve each target to its own module, not collapse into
/// a fallback `"root"` — exercised end-to-end through `AnalysisService.standard.analyzeProject`, the
/// real Swift parser, and `ProjectDiscovery`.
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

    /// Same layout, but through a resolved root URL — `NSTemporaryDirectory()` is itself a `/private`
    /// symlink on macOS, so this checks module resolution doesn't depend on resolved vs. unresolved
    /// path forms agreeing.
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
