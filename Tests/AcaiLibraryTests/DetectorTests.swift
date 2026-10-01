import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// Unit tests for every bundled build-system detector: `isPresent` (indicator-file presence), the
/// "prefer conventional source dir, fall back to root" rule, file-existence verification, and the
/// `requestedLanguages` filter. All bundled detector types are visible through `AcaiLibrary`'s re-exports.
@Suite("Build-system detectors", .timeLimit(.minutes(1)))
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

    /// A detector claims the directory it was asked about, whatever source dirs it reports under it.
    private func allClaim(_ specs: [SourceSpec], _ root: URL) -> Bool {
        !specs.isEmpty && specs.allSatisfy { $0.root.standardizedFileURL == root.standardizedFileURL }
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
            #expect(allClaim(detector.discoverSourceSpecs(at: root, requestedLanguages: []), root))
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
            // The nested source dirs sit under the root, but the claimed root is the folder itself.
            #expect(allClaim(specs, root))
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
            #expect(allClaim(detector.discoverSourceSpecs(at: root, requestedLanguages: []), root))
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
            #expect(allClaim(specs, root))
            let withJS = detector.discoverSourceSpecs(at: root, requestedLanguages: [.javaScript])
            #expect(withJS.contains { $0.language == .javaScript })
        }
    }

    /// `claim(at:requestedLanguages:)` is what the walk calls, so it has to agree with the two
    /// questions it answers at once.
    @Test func nodeClaimAgreesWithTheSeparateQuestions() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("src/a.ts", in: root)
            try write("src/b.js", in: root)

            let claim = detector.claim(at: root, requestedLanguages: [])
            #expect(claim.specs.map(\.language)
                == detector.discoverSourceSpecs(at: root, requestedLanguages: []).map(\.language))
            #expect(claim.withheldLanguages
                == detector.withheldLanguages(at: root, requestedLanguages: []))
            #expect(claim.withheldLanguages == [.javaScript])

            // Asked for explicitly, JavaScript is a spec rather than withheld.
            let explicit = detector.claim(at: root, requestedLanguages: [.javaScript])
            #expect(explicit.withheldLanguages.isEmpty)
            #expect(explicit.specs.map(\.language) == [.javaScript])
        }
    }

    /// A detector that answers only the two separate questions still claims correctly through the
    /// protocol's default.
    @Test func detectorWithoutItsOwnClaimUsesTheDefault() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: "// swift-tools-version:6.0")
            try write("Sources/App/main.swift", in: root)
            let claim = detector.claim(at: root, requestedLanguages: [])
            #expect(claim.specs.map(\.language) == [.swift])
            #expect(claim.withheldLanguages.isEmpty)
        }
    }

    @Test func nodePureJavaScriptProject() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("src/only.js", in: root)
            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.map(\.language) == [.javaScript])
            #expect(allClaim(specs, root))
        }
    }

    /// A monorepo declares its packages in `package.json`; each one contributes its own directories
    /// rather than the root being parsed wholesale.
    @Test func nodeReadsWorkspacePackages() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)
            try write("packages/ui/package.json", in: root, contents: "{}")
            try write("packages/ui/src/ui.ts", in: root)
            // A folder matching the glob but carrying no manifest is not a package.
            try write("packages/notes/README.md", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.map(\.language) == [.typeScript])
            #expect(dirNames(specs, for: .typeScript) == ["src", "src"])
            #expect(specs.first?.sourceDirs.map { $0.pathComponents.suffix(3).joined(separator: "/") }
                == ["packages/core/src", "packages/ui/src"])
            #expect(specs.first?.diagnostics.isEmpty == true)
        }
    }

    @Test func nodeReadsTheObjectFormOfWorkspacesAndItsExclusions() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: """
            {"workspaces": {"packages": ["packages/*", "!packages/legacy"]}}
            """)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)
            try write("packages/legacy/package.json", in: root, contents: "{}")
            try write("packages/legacy/src/old.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.first?.sourceDirs.map { $0.pathComponents.suffix(3).joined(separator: "/") }
                == ["packages/core/src"])
        }
    }

    /// A package whose `tsconfig.json` only extends a base used to yield nothing and fall back to
    /// probing; now it inherits the base's directories.
    @Test func nodeFollowsAWorkspacePackagesExtendsChain() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("tsconfig.base.json", in: root, contents: #"{"include": ["lib"]}"#)
            try write("packages/app/package.json", in: root, contents: "{}")
            try write("packages/app/tsconfig.json", in: root, contents: """
            {"extends": "../../tsconfig.base.json"}
            """)
            // The base resolves its own relative `include`, so this is the root's `lib`, not the package's.
            try write("lib/shared.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.first?.sourceDirs.map { $0.pathComponents.suffix(2).joined(separator: "/") }
                == ["\(root.lastPathComponent)/lib"])
        }
    }

    /// A `tsconfig` graph that leads back on itself is reported once, on one spec — it is a fact about
    /// the project, not about a language.
    @Test func nodeRecordsADiagnosticForATsconfigCycle() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": "./nested"}]}
            """)
            try write("nested/tsconfig.json", in: root, contents: #"{"references": [{"path": ".."}]}"#)
            try write("src/a.ts", in: root)
            try write("src/b.js", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [.typeScript, .javaScript])
            #expect(specs.count == 2)
            #expect(specs.map { $0.diagnostics.map(\.kind) } == [[.incompleteDiscovery], []])
        }
    }

    /// Workspaces that name nothing on disk mean the manifest does not describe this checkout: probing
    /// is still better than finding nothing, but it is a guess and is recorded as one.
    @Test func nodeRecordsADiagnosticWhenNoWorkspaceResolves() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("src/app.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(dirNames(specs, for: .typeScript) == ["src"])
            #expect(specs.first?.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(specs.first?.diagnostics.first?.location.filePath == "package.json")
        }
    }

    /// A workspace root that also holds sources of its own keeps them, but never falls back to the root
    /// itself — that would swallow every package.
    @Test func nodeKeepsAWorkspaceRootsOwnConventionalSourceDir() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("src/root.ts", in: root)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)
            // Outside both, and only reachable if the root itself were used as a source dir.
            try write("scratch/stray.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(specs.first?.sourceDirs.map { $0.pathComponents.suffix(2).joined(separator: "/") }
                == ["\(root.lastPathComponent)/src", "core/src"])
            #expect(specs.first?.diagnostics.isEmpty == true)
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
            #expect(allClaim(detector.discoverSourceSpecs(at: root, requestedLanguages: []), root))
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
            #expect(allClaim(detector.discoverSourceSpecs(at: root, requestedLanguages: []), root))
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
            #expect(allClaim(specs, root))
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
