import Foundation
import Testing
import AcaiCore

// Discovery cost O(directories × claims) because every claim check restandardised the directory
// under test, and source collection enumerated the tree once per source spec (#498). Timing either
// on shared CI hardware is flaky, so the shape is asserted through injected counters instead.

private let fixtureLanguage = CodeArtifact.SourceLanguage(rawValue: "scaling-fixture")

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

/// One made-up language per extension, each emitting a single type so an analysis over the fixture
/// produces several specs — the case that used to mean several walks of the same tree.
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

    private func standardizations(claimingPackages manifests: Int) throws -> (paths: Int, visited: Int, specs: Int) {
        let root = try makeTree(packages: 12, subdirectoriesEach: 2, manifests: manifests)
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = OperationCounter()
        let detector = ManifestDetector()
        let discovery = ProjectDiscovery(
            detectors: [detector], fallback: SilentFallback(), pathStandardizationCounter: counter
        )
        let specs = discovery.discoverSourceSpecs(in: root, requestedLanguages: [])
        return (counter.count, detector.probeCount, specs.count)
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
        let artifact = try await service.analyzeProject(
            at: root, allowedLanguages: [], respectingGitignore: false
        )

        #expect(artifact.types.count == 3)
        // `root`, `root/sub` and `root/sub/deeper` — once each, not once per registered language.
        #expect(counter.count == 3)
    }
}
