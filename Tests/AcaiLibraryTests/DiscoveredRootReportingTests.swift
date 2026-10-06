import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// What discovery recorded about the roots it claimed, as `HealthCheck` reports it: which
/// directories each root contributed, and whether any build system was recognised at all. Which
/// roots are *found* is `ProjectRootDiscoveryTests`; this is what a user can then read back.
@Suite("Discovered root reporting", .timeLimit(.minutes(1)))
struct DiscoveredRootReportingTests {

    /// Four projects side by side, nothing at the folder itself.
    private let fourProjects = SourceTreeFixture([
        "app-ios/Package.swift": "// file",
        "app-ios/Sources/App.swift": "class App {}",
        "web/package.json": "{}",
        "web/src/app.ts": "export class App {}",
        "proxy/pyproject.toml": "[project]",
        "proxy/src/app.py": "class App: pass"
    ])

    /// The directories each root contributed are what turn "fewer types than I expected" into a
    /// specific answer, so they reach the metadata alongside the root itself.
    @Test func eachRootRecordsTheSourceDirectoriesItContributed() async throws {
        try await fourProjects.analysed { artifact in
            let web = try #require(artifact.metadata.discoveredRoots.first { $0.path == "web" })
            #expect(web.sourceDirs == ["web/src"])
            let swiftRoot = try #require(artifact.metadata.discoveredRoots.first { $0.path == "app-ios" })
            #expect(swiftRoot.sourceDirs == ["app-ios/Sources"])
            #expect(artifact.metadata.discoveredRoots.allSatisfy { !$0.isFallback })
            #expect(!HealthCheck(artifact: artifact).report.isFallbackOnly)
        }
    }

    /// The case `--health` has to say out loud: no manifest anywhere, so every root is the
    /// fallback's and the file set is an extension match over the whole tree.
    @Test func aFolderWithNoManifestsRecordsItsRootAsTheFallbacks() async throws {
        let noManifests = SourceTreeFixture(["app-ios/Sources/App.swift": "class App {}"])

        try await noManifests.analysed { artifact in
            let roots = artifact.metadata.discoveredRoots
            #expect(roots.map(\.path) == ["."])
            #expect(roots.map(\.detector) == ["FallbackDetector"])
            #expect(roots.map(\.isFallback) == [true])
            #expect(roots.map(\.sourceDirs) == [["."]])
            #expect(HealthCheck(artifact: artifact).report.isFallbackOnly)
        }
    }

    /// One manifest is enough for the folder to have been scoped by a build system, even though the
    /// fallback also had to reach a language that manifest left out.
    @Test func aManifestAtTheRootMeansTheReportIsNotFallbackOnly() async throws {
        let oneManifest = SourceTreeFixture([
            "package.json": "{}",
            "src/app.ts": "export class App {}",
            "native/Foo.swift": "class Foo {}"
        ])

        try await oneManifest.analysed { artifact in
            let fallbacks = artifact.metadata.discoveredRoots.filter(\.isFallback)
            #expect(fallbacks.map(\.detector) == ["FallbackDetector"])
            #expect(!HealthCheck(artifact: artifact).report.isFallbackOnly)
        }
    }

    /// The report hands on exactly what the metadata recorded, so a reader of `--health` and a
    /// reader of the artifact never see different scopes.
    @Test func theReportHandsOnWhatTheMetadataRecorded() async throws {
        try await fourProjects.analysed { artifact in
            #expect(HealthCheck(artifact: artifact).report.discoveredRoots
                == artifact.metadata.discoveredRoots)
        }
    }
}
