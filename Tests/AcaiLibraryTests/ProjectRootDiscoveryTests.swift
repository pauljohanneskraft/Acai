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

    // MARK: - Merging several roots of one language

    /// Two Swift packages side by side are two specs, and both roots stay visible in the metadata.
    /// What merging them does with each field is pinned by `SourceSpecMergeTests` in `AcaiCoreTests`.
    @Test func twoRootsOfOneLanguageAreBothDiscovered() throws {
        try withTempDir { base in
            try write("one/Package.swift", in: base)
            try write("one/Sources/One.swift", in: base, contents: "class One {}")
            try write("two/Package.swift", in: base)
            try write("two/Sources/Two.swift", in: base, contents: "class Two {}")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])
            let swiftSpecs = specs.filter { $0.language == .swift }
            #expect(swiftSpecs.count == 2)

            #expect(Set(specs.discoveredRoots(relativeTo: base).map(\.path)) == ["one", "two"])
        }
    }

    // MARK: - Fixture and vendored projects

    /// The shape this repository has: a UI-test fixture package outside the real package's
    /// `Sources/`. Walking every directory would otherwise merge the fixture into the codebase's own
    /// Swift sources.
    @Test func aManifestInAFixtureDirectoryIsNotARoot() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/Acai/Real.swift", in: base, contents: "class Real {}")
            try write(
                "App/UITests/Fixtures/seeded/SamplePackage/Package.swift", in: base)
            try write(
                "App/UITests/Fixtures/seeded/SamplePackage/Sources/Sample.swift",
                in: base, contents: "class Sample {}")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(roots(specs, relativeTo: base) == ["./SwiftPackageManagerDetector"])
            #expect(!specs.flatMap(\.sourceDirs).contains { $0.path.contains("Fixtures") })
        }
    }

    @Test func vendoredAndTestDataProjectsAreNotRoots() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/Acai/Real.swift", in: base, contents: "class Real {}")
            try write("third_party/dep/package.json", in: base, contents: "{}")
            try write("third_party/dep/src/dep.ts", in: base, contents: "export class Dep {}")
            try write("testdata/sample/pyproject.toml", in: base, contents: "[project]")
            try write("testdata/sample/src/s.py", in: base, contents: "class S: pass")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(!roots(specs, relativeTo: base).contains { $0.hasPrefix("third_party") })
            #expect(!roots(specs, relativeTo: base).contains { $0.hasPrefix("testdata") })
        }
    }

    /// Matched on the name alone, so the convention holds whatever the repository capitalises it as.
    @Test func theNonRootNamesAreMatchedWithoutRegardToCase() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/Acai/Real.swift", in: base, contents: "class Real {}")
            try write("TestData/sample/package.json", in: base, contents: "{}")
            try write("TestData/sample/src/s.ts", in: base, contents: "export class S {}")

            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])
            #expect(!roots(specs, relativeTo: base).contains { $0.lowercased().hasPrefix("testdata") })
        }
    }

    /// The rule suppresses roots found *while walking a codebase*, never the folder the user pointed
    /// at — analysing a fixture package on its own still discovers it.
    @Test func aFixtureDirectoryAnalysedDirectlyIsStillARoot() throws {
        try withTempDir { base in
            let fixture = base.appendingPathComponent("Fixtures/SamplePackage", isDirectory: true)
            try write("Fixtures/SamplePackage/Package.swift", in: base)
            try write(
                "Fixtures/SamplePackage/Sources/Sample.swift", in: base, contents: "class Sample {}")

            let specs = discovery.discoverSourceSpecs(in: fixture, requestedLanguages: [])
            #expect(specs.map(\.language) == [.swift])
            #expect(roots(specs, relativeTo: fixture) == ["./SwiftPackageManagerDetector"])
        }
    }

    /// A caller that wants every manifest claimed can ask for it; the names are injected, not fixed.
    @Test func anEmptyNonRootSetClaimsFixtureProjectsAgain() throws {
        let claimingEverything = ProjectDiscovery(
            detectors: AnalysisService.standardDetectors,
            fallback: FallbackDetector(parsers: AnalysisService.standardParsers),
            excludedDirectories: LanguageRegistry(parsers: AnalysisService.standardParsers)
                .excludedDirectories,
            nonRootDirectories: []
        )
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/Acai/Real.swift", in: base, contents: "class Real {}")
            try write("Fixtures/SamplePackage/Package.swift", in: base)
            try write(
                "Fixtures/SamplePackage/Sources/Sample.swift", in: base, contents: "class Sample {}")

            let specs = claimingEverything.discoverSourceSpecs(in: base, requestedLanguages: [])
            #expect(roots(specs, relativeTo: base)
                .contains("Fixtures/SamplePackage/SwiftPackageManagerDetector"))
        }
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

    @Test func theFallbackDoesNotAddTheJavaScriptATypeScriptRootLeftOut() throws {
        try withTempDir { base in
            try write("package.json", in: base, contents: "{}")
            try write("src/app.ts", in: base, contents: "export class App {}")
            try write("jest.config.js", in: base, contents: "module.exports = {}")
            try write("lib/app.js", in: base, contents: "class App {}")
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(specs.map(\.language) == [.typeScript])
        }
    }

    @Test func anXcodeProjectBundleIsNotARootOfItsOwn() throws {
        try withTempDir { base in
            try write("Package.swift", in: base)
            try write("Sources/App.swift", in: base, contents: "class App {}")
            try write("App.xcodeproj/project.xcworkspace/contents.xcworkspacedata", in: base)
            let specs = discovery.discoverSourceSpecs(in: base, requestedLanguages: [])

            #expect(roots(specs, relativeTo: base) == ["./SwiftPackageManagerDetector"])
        }
    }

    // MARK: - Recorded on the artifact

    @Test func typesInOneRootResolveAgainstAnotherRootOfTheSameLanguage() async throws {
        try await withTempDirAsync { base in
            try write("core/build.gradle.kts", in: base)
            try write("core/src/main/kotlin/Base.kt", in: base, contents: """
                package com.core
                open class Base
                class Engine
                """)
            try write("app/build.gradle.kts", in: base)
            try write("app/src/main/kotlin/Derived.kt", in: base, contents: """
                package com.app
                import com.core.Base
                import com.core.Engine
                class Derived(val engine: Engine) : Base()
                """)
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            let edges = Set(artifact.relationships.map { "\($0.kind) \($0.source)->\($0.target)" })
            #expect(edges == [
                "inheritance com.app.Derived->com.core.Base",
                "composition com.app.Derived->com.core.Engine"
            ])
            #expect(artifact.metadata.discoveredRoots.map(\.path).sorted() == ["app", "core"])
        }
    }

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

    /// The directories each root contributed are what turn "fewer types than I expected" into a
    /// specific answer, so they reach the metadata alongside the root itself.
    @Test func eachRootRecordsTheSourceDirectoriesItContributed() async throws {
        try await withTempDirAsync { base in
            try writeFourProjects(in: base)
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            let web = try #require(artifact.metadata.discoveredRoots.first { $0.path == "web" })
            #expect(web.sourceDirs == ["web/src"])
            let swiftRoot = try #require(artifact.metadata.discoveredRoots.first { $0.path == "app-ios" })
            #expect(swiftRoot.sourceDirs == ["app-ios/Sources"])
            #expect(artifact.metadata.discoveredRoots.allSatisfy { !$0.isFallback })
        }
    }

    /// The case `--health` has to say out loud: no manifest anywhere, so every root is the fallback's
    /// and the file set is an extension match over the whole tree.
    @Test func aFolderWithNoManifestsRecordsItsRootAsTheFallbacks() async throws {
        try await withTempDirAsync { base in
            try write("app-ios/Sources/App.swift", in: base, contents: "class App {}")
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            let roots = artifact.metadata.discoveredRoots
            #expect(roots.map(\.path) == ["."])
            #expect(roots.map(\.detector) == ["FallbackDetector"])
            #expect(roots.map(\.isFallback) == [true])
            #expect(roots.map(\.sourceDirs) == [["."]])
            #expect(HealthCheck(artifact: artifact).report.isFallbackOnly)
        }
    }

    /// One manifest is enough for the folder to have been scoped by a build system, even though the
    /// fallback also had to reach a language it left out.
    @Test func aManifestAtTheRootMeansTheReportIsNotFallbackOnly() async throws {
        try await withTempDirAsync { base in
            try write("package.json", in: base, contents: "{}")
            try write("src/app.ts", in: base, contents: "export class App {}")
            try write("native/Foo.swift", in: base, contents: "class Foo {}")
            let artifact = try await AnalysisService.standard.analyzeProject(
                at: base, allowedLanguages: [])

            let fallbacks = artifact.metadata.discoveredRoots.filter(\.isFallback)
            #expect(fallbacks.map(\.detector) == ["FallbackDetector"])
            #expect(!HealthCheck(artifact: artifact).report.isFallbackOnly)
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
