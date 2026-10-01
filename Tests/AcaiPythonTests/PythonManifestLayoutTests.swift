import Foundation
import Testing
import AcaiCore
@testable import AcaiPython

/// One fixture per packaging tool that declares a layout, plus the fallback and failure paths.
@Suite("Python: pyproject.toml layout")
struct PythonManifestLayoutTests {

    private func makeProject(_ manifest: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("python-layout-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("pyproject.toml", in: root, contents: manifest)
        return root
    }

    private func withProject(_ manifest: String, _ body: (URL) throws -> Void) throws {
        let root = try makeProject(manifest)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func write(_ relativePath: String, in root: URL, contents: String = "x = 1\n") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func spec(_ root: URL) throws -> SourceSpec {
        try #require(
            PythonDetector().discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .python })
    }

    private func dirNames(_ root: URL) -> [String] {
        PythonDetector().discoverSourceSpecs(at: root, requestedLanguages: [])
            .first { $0.language == .python }?
            .sourceDirs.map(\.lastPathComponent) ?? []
    }

    // MARK: - One per layout tool

    @Test func setuptoolsPackageDir() throws {
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = "lib"}
        """) { root in
            try write("lib/app.py", in: root)
            try write("tests/test_app.py", in: root)
            #expect(dirNames(root) == ["lib"])
        }
    }

    /// A non-empty key maps a package to its own directory, so that directory is the source dir;
    /// file paths stay relative to the project root, which keeps the package name in them.
    @Test func setuptoolsPackageDirForANamedPackage() async throws {
        let root = try makeProject("""
        [tool.setuptools]
        package-dir = {"mypkg" = "src/mypkg"}
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("src/mypkg/models/user.py", in: root, contents: "class User:\n    pass\n")
        try write("tests/test_user.py", in: root, contents: "class TestUser:\n    pass\n")

        #expect(try spec(root).sourceDirs.map { Array($0.pathComponents.suffix(2)) } == [["src", "mypkg"]])
        let service = AnalysisService(
            parsers: [PythonCodeParser()],
            projectDiscovery: ProjectDiscovery(
                detectors: [PythonDetector()], fallback: FallbackDetector(parsers: [PythonCodeParser()])))
        let artifact = try await service.analyzeProject(at: root, allowedLanguages: [.python])
        #expect(artifact.flattened().compactMap(\.location?.filePath) == ["src/mypkg/models/user.py"])
    }

    @Test func setuptoolsPackagesFindWhere() throws {
        try withProject("""
        [tool.setuptools.packages.find]
        where = ["python"]
        """) { root in
            try write("python/app.py", in: root)
            #expect(dirNames(root) == ["python"])
        }
    }

    @Test func poetryPackagesFrom() throws {
        try withProject("""
        [tool.poetry]
        packages = [{include = "mypkg", from = "libs"}]
        """) { root in
            try write("libs/mypkg/__init__.py", in: root)
            #expect(dirNames(root) == ["libs"])
        }
    }

    /// Without `from`, `include` names the directory itself.
    @Test func poetryPackagesInclude() throws {
        try withProject("""
        [tool.poetry]
        packages = [{include = "mypkg"}]
        """) { root in
            try write("mypkg/__init__.py", in: root)
            #expect(dirNames(root) == ["mypkg"])
        }
    }

    @Test func hatchWheelPackages() throws {
        try withProject("""
        [tool.hatch.build.targets.wheel]
        packages = ["src/mypkg"]
        """) { root in
            try write("src/mypkg/__init__.py", in: root)
            #expect(dirNames(root) == ["mypkg"])
        }
    }

    // MARK: - Falling back

    @Test func aManifestWithNoLayoutKeysKeepsTheSrcProbe() throws {
        try withProject("""
        [project]
        name = "demo"
        """) { root in
            try write("src/app.py", in: root)
            #expect(dirNames(root) == ["src"])
        }
    }

    @Test func declaredDirectoriesThatDoNotExistKeepTheSrcProbe() throws {
        try withProject("""
        [tool.setuptools.packages.find]
        where = ["nowhere"]
        """) { root in
            try write("src/app.py", in: root)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["src"])
            let diagnostic = try #require(discovered.diagnostics.first)
            #expect(diagnostic.kind == .incompleteDiscovery)
            #expect(diagnostic.message.contains("'nowhere'"))
            #expect(diagnostic.message.contains("does not exist"))
        }
    }

    /// A usable declaration is kept even when a sibling one is dropped.
    @Test func aMissingDeclaredPathBesideAUsableOneIsReported() throws {
        try withProject("""
        [tool.setuptools.packages.find]
        where = ["python", "typo"]
        """) { root in
            try write("python/app.py", in: root)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["python"])
            #expect(discovered.diagnostics.map(\.message) == [
                "pyproject.toml declares 'typo' as a source directory, but it does not exist."
            ])
        }
    }

    @Test func aDeclaredPathMayNotEscapeTheProject() throws {
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = ".."}
        """) { root in
            try write("src/app.py", in: root)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["src"])
            #expect(discovered.diagnostics.first?.message.contains("'..'") == true)
            #expect(discovered.diagnostics.first?.message.contains("outside the project") == true)
        }
    }

    @Test func aSymlinkMayNotLeadADeclaredPathOutOfTheProject() throws {
        let outside = try makeProject("")
        defer { try? FileManager.default.removeItem(at: outside) }
        try write("secret.py", in: outside)
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = "lib"}
        """) { root in
            try write("src/app.py", in: root)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("lib"), withDestinationURL: outside)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["src"])
            #expect(discovered.diagnostics.first?.message.contains("'lib'") == true)
            #expect(discovered.diagnostics.first?.kind == .incompleteDiscovery)
        }
    }

    // MARK: - Line endings and escapes

    @Test func aCRLFManifestIsRead() throws {
        let manifest = ["# layout", "[tool.setuptools]", "package-dir = {\"\" = \"lib\"}", ""]
            .joined(separator: "\r\n")
        try withProject(manifest) { root in
            try write("lib/app.py", in: root)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["lib"])
            #expect(discovered.diagnostics.isEmpty)
        }
    }

    @Test func aUnicodeEscapeElsewhereDoesNotHideTheLayout() throws {
        try withProject(#"""
        [project]
        description = "Café tooling"

        [tool.setuptools]
        package-dir = {"" = "lib"}
        """#) { root in
            try write("lib/app.py", in: root)
            #expect(dirNames(root) == ["lib"])
        }
    }

    // MARK: - A malformed manifest

    @Test func aMalformedManifestFallsBackAndRecordsADiagnostic() throws {
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = "lib
        """) { root in
            try write("src/app.py", in: root)
            let discovered = try spec(root)
            #expect(discovered.sourceDirs.map(\.lastPathComponent) == ["src"])
            let diagnostic = try #require(discovered.diagnostics.first)
            #expect(diagnostic.location.filePath == "pyproject.toml")
            #expect(diagnostic.kind == .incompleteDiscovery)
            #expect(diagnostic.message.contains("pyproject.toml"))
        }
    }

    @Test func aWellFormedManifestRecordsNoDiagnostic() throws {
        try withProject("""
        [tool.hatch.build.targets.wheel]
        packages = ["src/mypkg"]
        """) { root in
            try write("src/mypkg/__init__.py", in: root)
            let specs = PythonDetector().discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.first { $0.language == .python }?.diagnostics.isEmpty == true)
        }
    }
}
