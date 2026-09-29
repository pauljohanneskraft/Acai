import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// Discovery walks the folder rather than only asking about the folder itself: a directory carrying
/// an indicator file is a project root wherever it sits, several roots coexist, and the fallback
/// covers only what no root claimed.
@Suite("Project root discovery", .timeLimit(.minutes(1)))
struct ProjectRootDiscoveryTests {

    private let discovery = AnalysisService.standard.projectDiscovery

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("root-discovery-\(UUID().uuidString)", isDirectory: true)
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

    /// The shape the issue describes: four projects side by side, nothing at the folder itself.
    private func writeFourProjects(in root: URL) throws {
        try write("app-ios/Package.swift", in: root)
        try write("app-ios/Sources/App.swift", in: root, contents: "class App {}")
        try write("app-android/settings.gradle.kts", in: root)
        try write("app-android/src/main/kotlin/App.kt", in: root, contents: "class App")
        try write("web/package.json", in: root, contents: "{}")
        try write("web/src/app.ts", in: root, contents: "export class App {}")
        try write("proxy/pyproject.toml", in: root, contents: "[project]")
        try write("proxy/src/app.py", in: root, contents: "class App: pass")
    }

    /// `(root-relative path, detector)` per spec, which is what identifies a discovered root.
    private func roots(_ specs: [SourceSpec], relativeTo base: URL) -> Set<String> {
        let basePath = base.resolvingSymlinksInPath().path
        return Set(specs.map { spec in
            let path = spec.root.resolvingSymlinksInPath().path
            let relative = path == basePath ? "." : String(path.dropFirst(basePath.count + 1))
            return "\(relative)/\(spec.detector)"
        })
    }

    // MARK: - Several roots below the folder

    @Test func eachSubdirectoryProjectIsItsOwnRoot() throws {
        try withTempDir { base in
            try writeFourProjects(in: base)
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(Set(specs.map(\.language)) == [.swift, .kotlin, .typeScript, .python])
            #expect(roots(specs, relativeTo: base) == [
                "app-ios/SwiftPackageManagerDetector",
                "app-android/JVMBuildSystemDetector",
                "web/NodeDetector",
                "proxy/PythonDetector"
            ])
        }
    }

    @Test func theSameShapeWithoutManifestsIsOneFallbackRootAtTheTop() throws {
        try withTempDir { base in
            try write("app-ios/Sources/App.swift", in: base, contents: "class App {}")
            try write("proxy/src/app.py", in: base, contents: "class App: pass")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(Set(specs.map(\.language)) == [.swift, .python])
            #expect(roots(specs, relativeTo: base) == ["./FallbackDetector"])
            #expect(specs.allSatisfy { $0.sourceDirs.map(\.standardizedFileURL) == [base] })
        }
    }

    @Test func aSinglePackageFolderIsStillOneRoot() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.map(\.language) == [.swift])
            #expect(specs.first?.sourceDirs.map(\.lastPathComponent) == ["Sources"])
            #expect(roots(specs, relativeTo: base) == ["./SwiftPackageManagerDetector"])
        }
    }

    // MARK: - The fallback covers only what no root claimed

    @Test func aManifestAtTheRootNoLongerHidesTheOtherLanguages() throws {
        try withTempDir { base in
            try write("package.json", in: base, contents: "{}")
            try write("src/app.ts", in: base, contents: "export class App {}")
            try write("native/Foo.swift", in: base, contents: "class Foo {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.first { $0.language == .typeScript }?.detector == "NodeDetector")
            #expect(specs.first { $0.language == .swift }?.detector == "FallbackDetector")
        }
    }

    @Test func aDetectorClaimingEveryPresentLanguageLeavesNothingForTheFallback() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.allSatisfy { $0.detector != "FallbackDetector" })
        }
    }

    // MARK: - Descent rules

    @Test func aNestedGradleModuleIsNotClaimedTwice() throws {
        try withTempDir { base in
            try write("settings.gradle.kts", in: base)
            try write("app/build.gradle.kts", in: base)
            try write("app/src/main/kotlin/App.kt", in: base, contents: "class App")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [.kotlin])

            #expect(specs.count == 1)
            #expect(specs.first?.sourceDirs.count == 1)
        }
    }

    @Test func aRootsOwnSourceDirectoryIsNotProbedAsANewRoot() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            // A manifest inside the package's own source dir belongs to that package, not to a
            // project of its own.
            try write("Sources/Vendored/package.json", in: base, contents: "{}")
            try write("Sources/Vendored/src/a.ts", in: base, contents: "export class A {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.allSatisfy { $0.detector != "NodeDetector" })
        }
    }

    @Test func excludedDirectoriesAreNeverDescendedInto() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            try write("node_modules/dep/package.json", in: base, contents: "{}")
            try write("node_modules/dep/src/a.ts", in: base, contents: "export class A {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.map(\.language) == [.swift])
        }
    }

    // MARK: - Recorded on the artifact

    @Test func theDiscoveredRootsReachTheArtifactsMetadata() async throws {
        try await withTempDirAsync { base in
            try writeFourProjects(in: base)
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            let found = Set(artifact.metadata.discoveredRoots.map(\.path))
            #expect(found == ["app-ios", "app-android", "web", "proxy"])
            let swiftRoot = try #require(artifact.metadata.discoveredRoots.first { $0.path == "app-ios" })
            #expect(swiftRoot.detector == "SwiftPackageManagerDetector")
            #expect(swiftRoot.languages == [.swift])
        }
    }

    @Test func aSingleRootFolderRecordsItselfAsTheRoot() async throws {
        try await withTempDirAsync { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            #expect(artifact.metadata.discoveredRoots.map(\.path) == ["."])
        }
    }

    private func withTempDirAsync(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("root-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir.standardizedFileURL)
    }
}
