import Foundation
import Testing
@testable import AcaiCore

/// Several specs become the roots recorded on the artifact: one entry per claimed directory, holding
/// every language that directory accounted for and every source directory it contributed.
@Suite("Discovered roots")
struct DiscoveredRootsTests {

    private let base = URL(fileURLWithPath: "/repo", isDirectory: true)

    private func spec(
        _ language: CodeArtifact.SourceLanguage,
        root: String,
        dirs: [String],
        detector: String,
        isFallback: Bool = false
    ) -> SourceSpec {
        let rootURL = root == "." ? base : base.appendingPathComponent(root, isDirectory: true)
        return SourceSpec(
            language: language,
            sourceDirs: dirs.map { base.appendingPathComponent($0, isDirectory: true) },
            root: rootURL,
            detector: detector,
            isFallback: isFallback
        )
    }

    @Test func eachRootRecordsItsPathDetectorAndSourceDirectories() {
        let roots = [
            spec(.swift, root: "app-ios", dirs: ["app-ios/Sources"], detector: "SwiftPackageManagerDetector"),
            spec(.dart, root: "proxy", dirs: ["proxy/lib", "proxy/test"], detector: "FlutterDetector")
        ].discoveredRoots(relativeTo: base)

        #expect(roots.map(\.path) == ["app-ios", "proxy"])
        #expect(roots.map(\.detector) == ["SwiftPackageManagerDetector", "FlutterDetector"])
        #expect(roots.map(\.sourceDirs) == [["app-ios/Sources"], ["proxy/lib", "proxy/test"]])
        #expect(roots.allSatisfy { !$0.isFallback })
    }

    /// One directory claimed for two languages is one root carrying both, with each language's
    /// directories — not two entries for the same path.
    @Test func aRootClaimingTwoLanguagesListsBothAndTheirDirectories() {
        let roots = [
            spec(.typeScript, root: "web", dirs: ["web/src"], detector: "NodeDetector"),
            spec(.javaScript, root: "web", dirs: ["web/legacy"], detector: "NodeDetector")
        ].discoveredRoots(relativeTo: base)

        #expect(roots.count == 1)
        #expect(roots[0].languages == [.typeScript, .javaScript])
        #expect(roots[0].sourceDirs == ["web/src", "web/legacy"])
    }

    /// Two languages scoped to the same directory must not list it twice: the reader is looking for
    /// which directories were in scope, not how many times each was claimed.
    @Test func aDirectoryClaimedForTwoLanguagesIsListedOnce() {
        let roots = [
            spec(.java, root: ".", dirs: ["src"], detector: "JVMBuildSystemDetector"),
            spec(.kotlin, root: ".", dirs: ["src"], detector: "JVMBuildSystemDetector")
        ].discoveredRoots(relativeTo: base)

        #expect(roots.count == 1)
        #expect(roots[0].path == ".")
        #expect(roots[0].sourceDirs == ["src"])
    }

    @Test func theAnalysedFolderItselfReadsAsADotForTheRootAndItsSources() {
        let roots = [spec(.swift, root: ".", dirs: ["."], detector: "FallbackDetector", isFallback: true)]
            .discoveredRoots(relativeTo: base)

        #expect(roots.map(\.path) == ["."])
        #expect(roots.map(\.sourceDirs) == [["."]])
        #expect(roots.map(\.isFallback) == [true])
    }

    /// Fallback-ness is per root: the same walk can scope one language by a manifest and reach the
    /// other only by file extension.
    @Test func onlyTheFallbacksOwnRootIsMarked() {
        let roots = [
            spec(.typeScript, root: ".", dirs: ["src"], detector: "NodeDetector"),
            spec(.swift, root: ".", dirs: ["."], detector: "FallbackDetector", isFallback: true)
        ].discoveredRoots(relativeTo: base)

        #expect(roots.map(\.detector) == ["NodeDetector", "FallbackDetector"])
        #expect(roots.map(\.isFallback) == [false, true])
    }
}
