import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

@Suite("CMake add_subdirectory() nested roots", .timeLimit(.minutes(1)))
struct CMakeNestedRootTests {

    private let detector = CFamilyBuildSystemDetector.cmake
    private let discovery = AnalysisService.standard.projectDiscovery

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cmake-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.standardizedFileURL)
    }

    private func withTempDirAsync(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cmake-nested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String = "// file") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func roots(_ specs: [SourceSpec], relativeTo base: URL) -> Set<String> {
        let basePath = base.resolvingSymlinksInPath().path
        return Set(specs.map { spec in
            let path = spec.root.resolvingSymlinksInPath().path
            let relative = path == basePath ? "." : String(path.dropFirst(basePath.count + 1))
            return "\(relative)/\(spec.detector)"
        })
    }

    // MARK: - Detector

    @Test func declaredSubdirectoriesWithAListfileAreNestedRoots() throws {
        try withTempDir { root in
            try write("CMakeLists.txt", in: root, contents: """
            project(Composed)
            add_subdirectory(core)
            add_subdirectory(ui EXCLUDE_FROM_ALL)
            add_subdirectory(assets)
            """)
            try write("main.c", in: root)
            try write("core/CMakeLists.txt", in: root, contents: "add_library(core core.c)")
            try write("core/core.c", in: root)
            try write("ui/CMakeLists.txt", in: root, contents: "add_library(ui ui.c)")
            try write("ui/ui.c", in: root)
            // Declared without a listfile of its own, so no root.
            try write("assets/logo.c", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [.c])
            #expect(specs.map(\.language) == [.c])
            #expect(specs.first?.root == root)
            #expect(specs.first?.nestedRootPaths.map(\.lastPathComponent) == ["core", "ui"])
            #expect(specs.first?.excludedPaths.isEmpty == true)
            #expect(specs.first?.diagnostics.isEmpty == true)
        }
    }

    @Test func makeDeclaresNoSubdirectories() throws {
        try withTempDir { root in
            try write("Makefile", in: root, contents: "add_subdirectory(core)")
            try write("main.c", in: root)
            try write("core/Makefile", in: root)
            let specs = CFamilyBuildSystemDetector.make.discoverSourceSpecs(at: root, requestedLanguages: [.c])
            #expect(specs.first?.nestedRootPaths.isEmpty == true)
        }
    }

    @Test func aSubdirectoryOutsideTheRootIsNoNestedRoot() throws {
        try withTempDir { base in
            let root = base.appendingPathComponent("project")
            try write("project/CMakeLists.txt", in: base, contents: """
            add_subdirectory(.)
            add_subdirectory(./)
            add_subdirectory(../sibling)
            add_subdirectory(\(base.path)/sibling)
            """)
            try write("project/main.c", in: base)
            try write("sibling/CMakeLists.txt", in: base)
            let spec = detector.discoverSourceSpecs(at: root, requestedLanguages: [.c]).first
            #expect(spec?.nestedRootPaths.isEmpty == true)
        }
    }

    @Test func aComputedSubdirectoryIsReportedWithItsLine() throws {
        try withTempDir { root in
            try write("CMakeLists.txt", in: root, contents: "project(P)\nadd_subdirectory(${EXTRA_MODULE})")
            try write("main.c", in: root)

            let spec = detector.discoverSourceSpecs(at: root, requestedLanguages: [.c]).first
            #expect(spec?.nestedRootPaths.isEmpty == true)
            #expect(spec?.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(spec?.diagnostics.first?.location.filePath == "CMakeLists.txt")
            #expect(spec?.diagnostics.first?.location.line == 2)
            #expect(spec?.diagnostics.first?.message.contains("${EXTRA_MODULE}") == true)
        }
    }

    // MARK: - Discovery

    @Test func declaredSubdirectoriesAreRootsOfTheirOwn() throws {
        try withTempDir { base in
            try write("CMakeLists.txt", in: base, contents: """
            project(Composed)
            add_subdirectory(core)
            add_subdirectory(ui)
            """)
            try write("main.c", in: base, contents: "int main(void) { return 0; }")
            try write("core/CMakeLists.txt", in: base, contents: "add_library(core core.c)")
            try write("core/core.c", in: base, contents: "int core(void) { return 1; }")
            try write("ui/CMakeLists.txt", in: base, contents: "add_library(ui ui.c)")
            try write("ui/ui.c", in: base, contents: "int ui(void) { return 2; }")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [.c])
            #expect(roots(specs, relativeTo: base) == [
                "./CFamilyBuildSystemDetector",
                "core/CFamilyBuildSystemDetector",
                "ui/CFamilyBuildSystemDetector"
            ])
        }
    }

    /// A listfile nothing declares is not a root: CMake does not build it, so neither does discovery.
    @Test func anUndeclaredNestedListfileIsNotARoot() throws {
        try withTempDir { base in
            try write("CMakeLists.txt", in: base, contents: "project(Single)")
            try write("main.c", in: base, contents: "int main(void) { return 0; }")
            try write("extra/CMakeLists.txt", in: base, contents: "add_library(e e.c)")
            try write("extra/e.c", in: base, contents: "int e(void) { return 1; }")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [.c])
            #expect(roots(specs, relativeTo: base) == ["./CFamilyBuildSystemDetector"])
        }
    }

    /// The walk never visits `vendor/`, so the sub-project there stays the declaring root's own sources.
    @Test func aSubdirectoryTheWalkSkipsStaysWithTheDeclaringRoot() async throws {
        try await withTempDirAsync { base in
            try write("CMakeLists.txt", in: base, contents: "add_subdirectory(vendor/zlib)")
            try write("main.c", in: base, contents: "int main(void) { return 0; }")
            try write("vendor/zlib/CMakeLists.txt", in: base, contents: "add_library(z z.c)")
            try write("vendor/zlib/z.c", in: base, contents: "int deflate(void) { return 1; }")

            let artifact = try await AnalysisService.standard.analyzeProject(at: base, allowedLanguages: [])
            #expect(artifact.metadata.filePaths.contains { $0.hasSuffix("vendor/zlib/z.c") })
        }
    }

    /// The declaring root's source directory still covers each nested root, so the overlap must dedupe.
    @Test func aComposedProjectParsesEachFileOnce() async throws {
        try await withTempDirAsync { base in
            try write("CMakeLists.txt", in: base, contents: "add_subdirectory(core)")
            try write("main.c", in: base, contents: "int main(void) { return 0; }")
            try write("core/CMakeLists.txt", in: base, contents: "add_library(core core.c)")
            try write("core/core.c", in: base, contents: "int core(void) { return 1; }")

            let artifact = try await AnalysisService.standard.analyzeProject(at: base, allowedLanguages: [])
            #expect(artifact.metadata.filePaths.filter { $0.hasSuffix("core.c") }.count == 1)
            #expect(artifact.metadata.discoveredRoots.map(\.path).sorted() == [".", "core"])
        }
    }
}
