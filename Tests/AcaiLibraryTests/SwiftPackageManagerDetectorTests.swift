import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// Unit tests for `SwiftPackageManagerDetector`'s manifest reading: declared target paths,
/// `exclude`/`sources`/`resources`, and the diagnostics a manifest that can't be fully read leaves
/// behind. Split out of `DetectorTests` (which keeps every other bundled detector) purely for size.
@Suite("Swift Package Manager detector", .timeLimit(.minutes(1)))
struct SwiftPackageManagerDetectorTests {

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("spm-detector-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.standardizedFileURL)
    }

    private func withTempDirAsync(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("spm-detector-tests-\(UUID().uuidString)", isDirectory: true)
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

    /// The last path components of a spec's source dirs (stable, location-independent assertions).
    private func dirNames(_ specs: [SourceSpec], for language: CodeArtifact.SourceLanguage) -> [String] {
        specs.first { $0.language == language }?.sourceDirs.map(\.lastPathComponent) ?? []
    }

    /// A detector claims the directory it was asked about, whatever source dirs it reports under it.
    private func allClaim(_ specs: [SourceSpec], _ root: URL) -> Bool {
        !specs.isEmpty && specs.allSatisfy { $0.root.standardizedFileURL == root.standardizedFileURL }
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
            #expect(allClaim(detector.discoverSourceSpecs(at: root, requestedLanguages: []), root))
            #expect(detector.discoverSourceSpecs(at: root, requestedLanguages: [.kotlin]).isEmpty)
        }
    }

    @Test func spmReadsDeclaredTargetPaths() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Demo",
                targets: [
                    .target(name: "Core", path: "Lib/Core", exclude: ["Fixtures"]),
                    .target(name: "Narrow", sources: ["Public"]),
                    .testTarget(name: "CoreTests"),
                ]
            )
            """)
            try write("Lib/Core/Core.swift", in: root)
            try write("Lib/Core/Fixtures/Sample.swift", in: root)
            try write("Sources/Narrow/Public/API.swift", in: root)
            try write("Sources/Narrow/Internal/Hidden.swift", in: root)
            try write("Tests/CoreTests/CoreTests.swift", in: root)
            // Not declared by any target, and outside every declared path.
            try write("Sources/Stray/Stray.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.diagnostics.isEmpty)
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["Core", "Public", "CoreTests"])
            #expect(spec.excludes(root.appendingPathComponent("Lib/Core/Fixtures/Sample.swift")))
            #expect(!spec.excludes(root.appendingPathComponent("Lib/Core/Core.swift")))
        }
    }

    /// The declared layout has to survive the whole pipeline, not just the detector: an excluded
    /// fixture, a `sources:`-narrowed folder and an undeclared target must not reach the artifact.
    @Test func spmDeclaredLayoutDecidesWhichFilesAreParsed() async throws {
        try await withTempDirAsync { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(
                name: "Demo",
                targets: [
                    .target(name: "Core", path: "Lib/Core", exclude: ["Fixtures"]),
                    .target(name: "Narrow", sources: ["Public"]),
                ]
            )
            """)
            try write("Lib/Core/Core.swift", in: root, contents: "struct Core {}")
            try write("Lib/Core/Fixtures/Sample.swift", in: root, contents: "struct Sample {}")
            try write("Sources/Narrow/Public/API.swift", in: root, contents: "struct API {}")
            try write("Sources/Narrow/Internal/Hidden.swift", in: root, contents: "struct Hidden {}")
            try write("Sources/Stray/Stray.swift", in: root, contents: "struct Stray {}")

            let artifact = try await AnalysisService.standard
                .analyzeProject(at: root, allowedLanguages: [.swift])
            #expect(artifact.flattened().map(\.name).sorted() == ["API", "Core"])
            #expect(artifact.metadata.parseDiagnostics.isEmpty)
        }
    }

    /// A manifest the reader can't fully interpret has to say so, not quietly guess.
    @Test func spmRecordsADiagnosticWhenItFallsBackToProbing() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(name: "Demo", targets: [.target(name: "Core")] + extraTargets)
            """)
            try write("Sources/Core/Core.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["Sources"])
            #expect(spec.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(spec.diagnostics.first?.location.filePath == "Package.swift")
        }
    }

    @Test func spmFindsTheOnlyTargetOfAKindDirectlyInItsPredefinedDirectory() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(
                name: "tool",
                targets: [.executableTarget(name: "tool"), .testTarget(name: "toolTests")]
            )
            """)
            try write("Sources/main.swift", in: root)
            try write("Tests/ToolTests.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.diagnostics.isEmpty)
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["Sources", "Tests"])
        }
    }

    /// `path` comes from the manifest, which is external input: a target that resolves outside the
    /// package is refused rather than followed.
    @Test func spmProbesWhenATargetPathEscapesThePackage() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(name: "Demo", targets: [.target(name: "Core", path: "../Elsewhere")])
            """)
            try write("Sources/Core/Core.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["Sources"])
            #expect(spec.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(spec.diagnostics.first?.message.contains("outside the package") == true)
        }
    }

    /// A `sources:` entry that leaves the target would widen it into a sibling, so it is dropped.
    @Test func spmIgnoresASourcesEntryOutsideItsTarget() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(
                name: "Demo",
                targets: [
                    .target(name: "Core"),
                    .target(name: "Narrow", sources: ["Public", "../Core"]),
                ]
            )
            """)
            try write("Sources/Core/Core.swift", in: root)
            try write("Sources/Narrow/Public/API.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.diagnostics.isEmpty)
            #expect(spec.sourceDirs.map(\.lastPathComponent) == ["Core", "Public"])
        }
    }

    /// SwiftPM copies resources rather than compiling them, so a fixture package declared as a
    /// resource is not part of the target's source — the usual way a test fixture is declared.
    @Test func spmSkipsSwiftFilesUnderADeclaredResource() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(
                name: "Demo",
                targets: [
                    .target(name: "Core"),
                    .testTarget(name: "CoreTests", resources: [.copy("Fixtures")]),
                ]
            )
            """)
            try write("Sources/Core/Core.swift", in: root)
            try write("Tests/CoreTests/CoreTests.swift", in: root)
            try write("Tests/CoreTests/Fixtures/Package.swift", in: root)
            try write("Tests/CoreTests/Fixtures/Sources/Fixture/Fixture.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            let fixtureSource = "Tests/CoreTests/Fixtures/Sources/Fixture/Fixture.swift"
            #expect(spec.diagnostics.isEmpty)
            #expect(spec.excludes(root.appendingPathComponent(fixtureSource)))
            #expect(!spec.excludes(root.appendingPathComponent("Tests/CoreTests/CoreTests.swift")))
        }
    }

    @Test func spmProbesRatherThanDroppingATargetWhoseDirectoryIsMissing() throws {
        let detector = SwiftPackageManagerDetector()
        try withTempDir { root in
            try write("Package.swift", in: root, contents: """
            let package = Package(name: "Demo", targets: [.target(name: "Core"), .target(name: "Gone")])
            """)
            try write("Sources/Core/Core.swift", in: root)

            let spec = try #require(
                detector.discoverSourceSpecs(at: root, requestedLanguages: []).first { $0.language == .swift })
            #expect(spec.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(spec.diagnostics.first?.message.contains("`Gone`") == true)
        }
    }
}
