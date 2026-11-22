import Foundation
import Testing
@testable import AcaiCore

private let fixtureLanguage = CodeArtifact.SourceLanguage(rawValue: "scaling-fixture")

/// Claims a directory holding a `manifest` for `fx1`, probing through the reads it is handed.
private struct IndicatorDetector: BuildSystemDetector {
    func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["manifest"]).present(at: root)
    }

    func isPresent(at root: URL, reading reads: DirectoryReadCache) -> Bool {
        IndicatorFiles(["manifest"]).present(at: root, reading: reads)
    }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        [SourceSpec(language: CodeArtifact.SourceLanguage(rawValue: "fx1"), sourceDirs: [root], root: root)]
    }
}

/// Claims the directory it is probed at as that directory's only source directory, so each package
/// in the fixture contributes a claim without claiming a subtree of its own.
private final class ManifestDetector: BuildSystemDetector, @unchecked Sendable {
    private let lock = NSLock()
    private var probes = 0

    /// How many directories the walk visited: ``isPresent(at:)`` is asked once per directory.
    var probeCount: Int {
        lock.withLock { probes }
    }

    func isPresent(at root: URL) -> Bool {
        lock.withLock { probes += 1 }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest").path)
    }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        [SourceSpec(language: fixtureLanguage, sourceDirs: [root], root: root)]
    }
}

private struct SilentFallback: BuildSystemDetector {
    func isPresent(at root: URL) -> Bool { false }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        []
    }
}

/// One made-up language per extension, each emitting a single type, so the fixture yields several specs.
private struct FixtureParser: CodeParser {
    let language: CodeArtifact.SourceLanguage
    let fileExtensions: [String]
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = "Type_\(fileExtensions[0])"
        return CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: [fileName]),
            types: [TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public)]
        )
    }
}

@Suite("Discovery and collection scaling", .timeLimit(.minutes(1)))
struct DiscoveryScalingTests {

    /// `root/pkg<i>/sub<j>`, with a `manifest` in the first `manifests` packages. Shape is fixed so
    /// two runs differing only in how many packages claim visit exactly the same directories.
    private func makeTree(packages: Int, subdirectoriesEach: Int, manifests: Int) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("acai-discovery-scaling-\(UUID().uuidString)", isDirectory: true)
        for package in 0..<packages {
            let directory = root.appendingPathComponent("pkg\(package)", isDirectory: true)
            for sub in 0..<subdirectoriesEach {
                try fileManager.createDirectory(
                    at: directory.appendingPathComponent("sub\(sub)", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            if package < manifests {
                try "".write(to: directory.appendingPathComponent("manifest"), atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    private struct DiscoveryCounts {
        let paths: Int
        let comparisons: Int
        let visited: Int
        let specs: Int
    }

    private func standardizations(claimingPackages manifests: Int) throws -> DiscoveryCounts {
        let root = try makeTree(packages: 12, subdirectoriesEach: 2, manifests: manifests)
        defer { try? FileManager.default.removeItem(at: root) }
        let standardizations = OperationCounter()
        let comparisons = OperationCounter()
        let detector = ManifestDetector()
        let discovery = ProjectDiscovery(
            detectors: [detector], fallback: SilentFallback(),
            pathStandardizationCounter: standardizations, claimComparisonCounter: comparisons
        )
        let specs = discovery.discoverSourceSpecs(in: root, requestedLanguages: [])
        return DiscoveryCounts(
            paths: standardizations.count, comparisons: comparisons.count,
            visited: detector.probeCount, specs: specs.count
        )
    }

    @Test("a visited directory's path is standardised at most once")
    func standardisesEachVisitedDirectoryAtMostOnce() throws {
        let walk = try standardizations(claimingPackages: 12)
        #expect(walk.specs == 12)
        #expect(walk.visited == 37)
        #expect(walk.paths <= walk.visited)
    }

    @Test("standardisation does not grow with the number of claims")
    func standardisationIsIndependentOfClaimCount() throws {
        let oneClaim = try standardizations(claimingPackages: 1)
        let everyPackage = try standardizations(claimingPackages: 12)
        #expect(oneClaim.visited == everyPackage.visited)
        #expect(oneClaim.paths == everyPackage.paths)
    }

    @Test("a listed directory takes its standardised path from its parent's")
    func listedDirectoriesDeriveTheirStandardisedPath() throws {
        // Only the root's own children, whose parent the walk never standardised, reach the filesystem.
        #expect(try standardizations(claimingPackages: 12).paths == 12)
    }

    @Test("an ancestor check compares only the claims on the candidate's own path")
    func claimComparisonsAreIndependentOfClaimCount() throws {
        let oneClaim = try standardizations(claimingPackages: 1)
        let everyPackage = try standardizations(claimingPackages: 12)
        #expect(oneClaim.comparisons == everyPackage.comparisons)
    }

    @Test("a multi-language tree is enumerated once per analysis, not once per language")
    func enumeratesTreeOncePerAnalysis() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("acai-collection-scaling-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        for (index, fileExtension) in ["fx1", "fx2", "fx3"].enumerated() {
            try "source".write(
                to: (index == 0 ? root : nested).appendingPathComponent("file\(index).\(fileExtension)"),
                atomically: true, encoding: .utf8
            )
        }

        let counter = OperationCounter()
        let service = AnalysisService(
            parsers: ["fx1", "fx2", "fx3"].map {
                FixtureParser(language: CodeArtifact.SourceLanguage(rawValue: $0), fileExtensions: [$0])
            },
            directoryEnumerationCounter: counter
        )
        let artifact = try await service.analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.types.count == 3)
        // `root`, `root/sub` and `root/sub/deeper`, once each across the whole analysis.
        #expect(counter.count == 3)
    }

    /// `directories` and `files` are relative to a fresh temporary root.
    private func makeTree(directories: [String], files: [String]) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("acai-shared-reads-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for directory in directories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true), withIntermediateDirectories: true
            )
        }
        for file in files {
            try "source".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func analyzeManifestPackage(in root: URL, respectingGitignore: Bool) async throws -> Int {
        let counter = OperationCounter()
        let service = AnalysisService(
            parsers: [FixtureParser(language: CodeArtifact.SourceLanguage(rawValue: "fx1"), fileExtensions: ["fx1"])],
            projectDiscovery: ProjectDiscovery(detectors: [IndicatorDetector()], fallback: SilentFallback()),
            directoryEnumerationCounter: counter
        )
        let artifact = try await service.analyzeProject(
            at: root, allowedLanguages: [], respectingGitignore: respectingGitignore
        )
        #expect(artifact.types.count == 1)
        return counter.count
    }

    @Test("discovery lists the directories it walks through the analysis's reads")
    func discoveryReadsThroughTheAnalysis() async throws {
        let root = try makeTree(directories: ["a", "pkg"], files: ["pkg/manifest", "pkg/file.fx1"])
        defer { try? FileManager.default.removeItem(at: root) }

        // Only discovery lists `root` and `a`: `.gitignore` is off and the one spec is `pkg`.
        #expect(try await analyzeManifestPackage(in: root, respectingGitignore: false) == 3)
    }

    @Test("`.gitignore` loading lists through the analysis's reads")
    func gitignoreReadsThroughTheAnalysis() async throws {
        let root = try makeTree(directories: ["fixtures", "pkg"], files: ["pkg/manifest", "pkg/file.fx1"])
        defer { try? FileManager.default.removeItem(at: root) }

        // Only the `.gitignore` walk lists `fixtures`, which discovery never enters.
        #expect(try await analyzeManifestPackage(in: root, respectingGitignore: true) == 3)
    }

    @Test("the fallback walks through the reads discovery hands it")
    func fallbackReadsThroughDiscovery() throws {
        let root = try makeTree(directories: ["fixtures"], files: ["fixtures/file.fx1"])
        defer { try? FileManager.default.removeItem(at: root) }
        let listings = OperationCounter()
        let parser = FixtureParser(language: CodeArtifact.SourceLanguage(rawValue: "fx1"), fileExtensions: ["fx1"])

        let reads = DirectoryReadCache(listingCounter: listings)
        let specs = ProjectDiscovery(detectors: [], fallback: FallbackDetector(parsers: [parser]))
            .discoverSourceSpecs(in: root, requestedLanguages: [], reading: reads)

        #expect(specs.count == 1)
        // Discovery lists `root`; only the fallback's walk lists `fixtures`.
        #expect(listings.count == 2)
    }

    @Test("the fallback does not walk for languages discovery already claimed")
    func fallbackSkipsClaimedLanguages() throws {
        let root = try makeTree(directories: ["fixtures", "pkg"], files: ["pkg/manifest", "pkg/file.fx1"])
        defer { try? FileManager.default.removeItem(at: root) }
        let listings = OperationCounter()
        let parser = FixtureParser(language: CodeArtifact.SourceLanguage(rawValue: "fx1"), fileExtensions: ["fx1"])

        let reads = DirectoryReadCache(listingCounter: listings)
        let specs = ProjectDiscovery(detectors: [IndicatorDetector()], fallback: FallbackDetector(parsers: [parser]))
            .discoverSourceSpecs(in: root, requestedLanguages: [], reading: reads)

        #expect(specs.map(\.isFallback) == [false])
        // `root` and `pkg`; with every language claimed, nothing walks into `fixtures`.
        #expect(listings.count == 2)
    }

    @Test("a file's contents are read from disk once however often they are asked for")
    func fileContentsAreReadOnce() throws {
        let root = try makeTree(directories: [], files: ["settings.gradle"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fileReads = OperationCounter()
        let reads = DirectoryReadCache(listingCounter: nil, fileReadCounter: fileReads)
        let settings = root.appendingPathComponent("settings.gradle")

        #expect(reads.contents(of: settings) == "source")
        #expect(reads.contents(of: settings) == "source")
        #expect(reads.contents(of: root.appendingPathComponent("settings.gradle.kts")) == nil)
        #expect(fileReads.count == 1)
    }

    @Test("an indicator probe reads the directory's listing rather than the disk")
    func indicatorProbeReadsTheListing() throws {
        let root = try makeTree(directories: [], files: ["manifest"])
        defer { try? FileManager.default.removeItem(at: root) }
        let listings = OperationCounter()
        let reads = DirectoryReadCache(listingCounter: listings)

        #expect(IndicatorFiles(["manifest"]).present(at: root, reading: reads))
        #expect(!IndicatorFiles(["MANIFEST.in"]).present(at: root, reading: reads))
        #expect(listings.count == 1)
    }
}
