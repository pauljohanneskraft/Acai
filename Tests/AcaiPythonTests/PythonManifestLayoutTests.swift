import Foundation
import Testing
import AcaiCore
@testable import AcaiPython

/// One fixture per packaging tool that declares a layout, plus the fallback and failure paths.
@Suite("Python: pyproject.toml layout")
struct PythonManifestLayoutTests {

    private func withProject(_ manifest: String, _ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("python-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("pyproject.toml", in: root, contents: manifest)
        try body(root.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String = "x = 1\n") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
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
            #expect(dirNames(root) == ["src"])
        }
    }

    @Test func aDeclaredPathMayNotEscapeTheProject() throws {
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = "../../etc"}
        """) { root in
            try write("src/app.py", in: root)
            #expect(dirNames(root) == ["src"])
        }
    }

    // MARK: - A malformed manifest

    @Test func aMalformedManifestFallsBackAndRecordsADiagnostic() throws {
        try withProject("""
        [tool.setuptools]
        package-dir = {"" = "lib
        """) { root in
            try write("src/app.py", in: root)
            let specs = PythonDetector().discoverSourceSpecs(at: root, requestedLanguages: [])
            let spec = try #require(specs.first { $0.language == .python })
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["src"])
            let diagnostic = try #require(spec.diagnostics.first)
            #expect(diagnostic.location.filePath == "pyproject.toml")
            #expect(diagnostic.kind == .error)
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
