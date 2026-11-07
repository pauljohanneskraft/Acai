import Foundation
import Testing
import AcaiCore

private let fixtureLanguage = CodeArtifact.SourceLanguage(rawValue: "fixture")
private let fallbackLanguage = CodeArtifact.SourceLanguage(rawValue: "fixture-fallback")

private final class ManifestDetector: BuildSystemDetector, @unchecked Sendable {
    private let lock = NSLock()
    private var probes = 0
    let cancelOnFirstProbe: Bool

    init(cancelOnFirstProbe: Bool = false) {
        self.cancelOnFirstProbe = cancelOnFirstProbe
    }

    var probeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return probes
    }

    func isPresent(at root: URL) -> Bool {
        lock.lock()
        probes += 1
        lock.unlock()
        if cancelOnFirstProbe {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest").path)
    }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        [SourceSpec(language: fixtureLanguage, sourceDirs: [root], root: root)]
    }
}

private struct AlwaysFallback: BuildSystemDetector {
    func isPresent(at root: URL) -> Bool { true }

    func discoverSourceSpecs(at root: URL, requestedLanguages: [CodeArtifact.SourceLanguage]) -> [SourceSpec] {
        [SourceSpec(language: fallbackLanguage, sourceDirs: [root], root: root)]
    }
}

@Suite("Project discovery cancellation", .timeLimit(.minutes(1)))
struct ProjectDiscoveryCancellationTests {
    private func makeTwoPackageTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiDiscoveryCancellation-\(UUID().uuidString)", isDirectory: true)
        for name in ["Alpha", "Beta"] {
            let package = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try "".write(to: package.appendingPathComponent("manifest"), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func discoveredRootNames(
        in root: URL, detector: ManifestDetector, cancellingFirst: Bool = false
    ) async -> [String] {
        let discovery = ProjectDiscovery(detectors: [detector], fallback: AlwaysFallback())
        return await Task.detached {
            if cancellingFirst {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return discovery.discoverSourceSpecs(in: root, requestedLanguages: []).map(\.root.lastPathComponent)
        }.value
    }

    @Test func anUncancelledWalkFindsBothPackagesAndTheFallback() async throws {
        let root = try makeTwoPackageTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let names = await discoveredRootNames(in: root, detector: ManifestDetector())

        #expect(names == ["Alpha", "Beta", root.lastPathComponent])
    }

    @Test func aCancelledWalkFindsNothingAndSkipsTheFallback() async throws {
        let root = try makeTwoPackageTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = ManifestDetector()

        let names = await discoveredRootNames(in: root, detector: detector, cancellingFirst: true)

        #expect(names.isEmpty)
        #expect(detector.probeCount == 0)
    }

    @Test func cancellingMidWalkStopsDescending() async throws {
        let root = try makeTwoPackageTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = ManifestDetector(cancelOnFirstProbe: true)

        let names = await discoveredRootNames(in: root, detector: detector)

        #expect(names.isEmpty)
        #expect(detector.probeCount == 1)
    }
}
