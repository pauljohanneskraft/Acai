import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// Unit tests for every bundled build-system detector: `isPresent` (indicator-file presence), the
/// "prefer conventional source dir, fall back to root" rule, file-existence verification, and the
/// `requestedLanguages` filter. All bundled detector types are visible through `AcaiLibrary`'s re-exports.
@Suite("Build-system detectors")
struct DetectorTests {

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("detector-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String = "// file") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The last path components of a spec's source dirs (stable, location-independent assertions).
    private func dirNames(_ specs: [SourceSpec], for language: CodeArtifact.SourceLanguage) -> [String] {
        specs.first { $0.language == language }?.sourceDirs.map(\.lastPathComponent) ?? []
    }

    // MARK: - Swift Package Manager

    @Test func spmDetectsManifestAndPrefersSourcesDir() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("Package.swift", in: root)
            #expect(detector.isPresent(at: root))

            #expect(dirNames(detector.discoverSourceSpecs(at: root, requestedLanguages: []), for: .swift)
                == [root.lastPathComponent])
            try write("Sources/A.swift", in: root)
            #expect(dirNames(detector.discoverSourceSpecs(at: root, requestedLanguages: []), for: .swift)
                == ["Sources"])
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: [.kotlin]).isEmpty)
        }
    }

    // MARK: - Xcode

    @Test func xcodeDetectsProjectBundle() throws {
        let detector = XcodeDetector()
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
            #expect(detector.isPresent(at: root))
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: []).first?.language == .swift)
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: [.java]).isEmpty)
        }
    }

    // MARK: - JVM (Gradle / Maven)

    @Test func gradleDetectsAndFindsConventionalSourceDirs() throws {
        let detector = JVMBuildSystemDetector.gradle
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("build.gradle.kts", in: root)
            #expect(detector.isPresent(at: root))

            try write("src/main/kotlin/A.kt", in: root)
            try write("src/main/java/B.java", in: root)
            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(dirNames(specs, for: .kotlin) == ["kotlin"])
            #expect(dirNames(specs, for: .java) == ["java"])
            let kotlinOnly = detector.discoverSourceSpecs(at: root, requestedLanguages: [.kotlin])
            #expect(kotlinOnly.map(\.language) == [.kotlin])
        }
    }

    @Test func mavenFallsBackToRootForLooseSources() throws {
        let detector = JVMBuildSystemDetector.maven
        try withTempDir { root in
            try write("pom.xml", in: root)
            #expect(detector.isPresent(at: root))
            try write("Main.java", in: root)
            #expect(dirNames(detector.discoverSourceSpecs(at: root, requestedLanguages: []), for: .java)
                == [root.lastPathComponent])
        }
    }

    // MARK: - Node (TS / JS)

    @Test func nodeDetectsAndPrefersTypeScript() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("package.json", in: root, contents: "{}")
            #expect(detector.isPresent(at: root))

            // JS is suppressed by default when TS is present, unless explicitly requested.
            try write("src/a.ts", in: root)
            try write("src/b.js", in: root)
            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.map(\.language) == [.typeScript])
            let withJS = detector.discoverSourceSpecs(at: root, requestedLanguages: [.javaScript])
            #expect(withJS.contains { $0.language == .javaScript })
        }
    }

    @Test func nodePureJavaScriptProject() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("src/only.js", in: root)
            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.map(\.language) == [.javaScript])
        }
    }

    // MARK: - Flutter / Dart

    @Test func flutterDetectsAndPrefersLibDir() throws {
        let detector = FlutterDetector()
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("pubspec.yaml", in: root, contents: "name: app")
            #expect(detector.isPresent(at: root))
            // Manifest alone isn't enough — the detector verifies matching source files exist.
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: []).isEmpty)
            try write("lib/main.dart", in: root)
            #expect(dirNames(detector.discoverSourceSpecs(at: root, requestedLanguages: []), for: .dart)
                == ["lib"])
        }
    }

    // MARK: - Python

    @Test func pythonDetectsManifestAndVerifiesSources() throws {
        let detector = PythonDetector()
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("pyproject.toml", in: root, contents: "[project]")
            #expect(detector.isPresent(at: root))
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: []).isEmpty)
            try write("src/app.py", in: root)
            #expect(dirNames(detector.discoverSourceSpecs(at: root, requestedLanguages: []), for: .python)
                == ["src"])
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: [.swift]).isEmpty)
        }
    }

    // MARK: - C-family (CMake / Make / Meson)

    @Test func cmakeDetectsCAndCpp() throws {
        let detector = CFamilyBuildSystemDetector.cmake
        try withTempDir { root in
            #expect(!detector.isPresent(at: root))
            try write("CMakeLists.txt", in: root)
            #expect(detector.isPresent(at: root))

            try write("main.c", in: root)
            try write("widget.cpp", in: root)
            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.contains { $0.language == .c })
            #expect(specs.contains { $0.language == .cpp })
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: [.cpp]).map(\.language) == [.cpp])
        }
    }

    @Test func makeAndMesonIndicatorFiles() throws {
        try withTempDir { root in
            try write("Makefile", in: root)
            #expect(CFamilyBuildSystemDetector.make.isPresent(at: root))
            #expect(!CFamilyBuildSystemDetector.meson.isPresent(at: root))
            try write("meson.build", in: root)
            #expect(CFamilyBuildSystemDetector.meson.isPresent(at: root))
        }
    }
}
