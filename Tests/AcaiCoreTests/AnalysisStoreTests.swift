import Foundation
import Testing
@testable import AcaiCore

@Suite("AnalysisStore")
struct AnalysisStoreTests {
    private func makeStore() throws -> (store: AnalysisStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalysisStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (AnalysisStore(directory: directory), directory)
    }

    private func makeArtifact(toolVersion: String = "1.0.0") -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["Foo.swift"], toolVersion: toolVersion))
    }

    private let fingerprint = CodeStateFingerprint.fileSystem(
        latestModification: Date(timeIntervalSince1970: 1000), fileCount: 1, contentDigest: 42)

    // MARK: - Round trip

    @Test func writeThenLookupByResolvedPathRoundTrips() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = makeArtifact()

        try store.write(artifact, sourcePath: "/tmp/proj", fingerprint: fingerprint)

        guard case .entry(let entry) = store.lookup(forResolvedPath: "/tmp/proj") else {
            Issue.record("Expected an entry")
            return
        }
        #expect(entry.artifact == artifact)
        #expect(entry.sourcePath == "/tmp/proj")
        #expect(entry.fingerprint == fingerprint)
    }

    @Test func writeThenLookupByNameRoundTrips() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = makeArtifact()

        let url = try store.write(artifact, sourcePath: "/tmp/proj", fingerprint: fingerprint, named: "myapp")

        #expect(url.lastPathComponent == "myapp.json")
        guard case .entry(let entry) = store.lookup(named: "myapp") else {
            Issue.record("Expected an entry")
            return
        }
        #expect(entry.artifact == artifact)

        // A name is also a valid way to reach the same entry by path.
        guard case .entry(let byPath) = store.lookup(forResolvedPath: "/tmp/proj") else {
            Issue.record("Expected the named entry to be found by path too")
            return
        }
        #expect(byPath.sourcePath == "/tmp/proj")
    }

    @Test func lookupForAnUnknownPathOrNameIsAbsent() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.lookup(forResolvedPath: "/no/such/path") == .absent)
        #expect(store.lookup(named: "nope") == .absent)
    }

    // MARK: - Convergence

    @Test func aLaterNamedWriteSupersedesAnEarlierUnnamedOne() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = makeArtifact()

        try store.write(artifact, sourcePath: "/tmp/proj", fingerprint: fingerprint)
        let staleFingerprint = CodeStateFingerprint.fileSystem(
            latestModification: .distantPast, fileCount: 99, contentDigest: 0)
        try store.write(artifact, sourcePath: "/tmp/proj", fingerprint: staleFingerprint, named: "myapp")

        guard case .entry(let entry) = store.lookup(forResolvedPath: "/tmp/proj") else {
            Issue.record("Expected an entry")
            return
        }
        #expect(entry.fingerprint == staleFingerprint)
    }

    @Test func aSecondUnnamedWriteForTheSamePathOverwritesTheFirst() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.write(makeArtifact(), sourcePath: "/tmp/proj", fingerprint: fingerprint)
        let updated = makeArtifact()
        let secondFingerprint = CodeStateFingerprint.fileSystem(
            latestModification: Date(timeIntervalSince1970: 2000), fileCount: 2, contentDigest: 7)
        try store.write(updated, sourcePath: "/tmp/proj", fingerprint: secondFingerprint)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.count == 1)
        guard case .entry(let entry) = store.lookup(forResolvedPath: "/tmp/proj") else {
            Issue.record("Expected an entry")
            return
        }
        #expect(entry.fingerprint == secondFingerprint)
    }

    // MARK: - Legacy decode

    @Test func aLegacyBareArtifactFileStillDecodesByName() throws {
        let (store, directory) = try makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = makeArtifact()
        try JSONEncoder().encode(artifact).write(to: store.url(forName: "legacy"))

        guard case .legacyArtifact(let decoded) = store.lookup(named: "legacy") else {
            Issue.record("Expected a legacyArtifact")
            return
        }
        #expect(decoded == artifact)
    }

    @Test func aLegacyEntryIsNeverCurrent() throws {
        let (store, directory) = try makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try JSONEncoder().encode(makeArtifact()).write(to: store.url(forName: "legacy"))

        // A legacy entry never resolves via lookup(forResolvedPath:) since it never recorded a
        // source path — a caller must fall back to full re-analysis for it.
        #expect(store.lookup(forResolvedPath: "/tmp/proj") == .absent)
    }

    @Test func aCorruptFileIsAbsentNotThrown() throws {
        let (store, directory) = try makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: store.url(forName: "corrupt"))

        #expect(store.lookup(named: "corrupt") == .absent)
    }

    // MARK: - Freshness

    @Test func entryIsCurrentOnlyWhenPathFingerprintAndToolVersionAllMatch() throws {
        let entry = AnalysisStore.Entry(artifact: makeArtifact(toolVersion: "1.0.0"), sourcePath: "/tmp/proj",
            fingerprint: fingerprint)

        #expect(entry.isCurrent(sourcePath: "/tmp/proj", fingerprint: fingerprint, toolVersion: "1.0.0"))
        #expect(!entry.isCurrent(sourcePath: "/tmp/other", fingerprint: fingerprint, toolVersion: "1.0.0"))
        #expect(!entry.isCurrent(sourcePath: "/tmp/proj", fingerprint: .git(headCommitSHA: "x", isDirty: false),
            toolVersion: "1.0.0"))
        #expect(!entry.isCurrent(sourcePath: "/tmp/proj", fingerprint: fingerprint, toolVersion: "2.0.0"))
    }

    @Test func entryWithMismatchedToolVersionIsNeverCurrent() throws {
        let entry = AnalysisStore.Entry(
            artifact: makeArtifact(toolVersion: "0.9.0"), sourcePath: "/tmp/proj", fingerprint: fingerprint)
        #expect(!entry.isCurrent(sourcePath: "/tmp/proj", fingerprint: fingerprint, toolVersion: "1.0.0"))
    }
}
