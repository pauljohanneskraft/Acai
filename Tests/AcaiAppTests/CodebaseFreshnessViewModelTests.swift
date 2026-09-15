import Foundation
import Testing
@testable import AcaiApp

@Suite("Codebase freshness (issue #178)")
@MainActor
struct CodebaseFreshnessViewModelTests {
    private func makeModel(sourceDir: URL, baseDir: URL, codebaseID: UUID) -> ProjectBrowserViewModel {
        let store = ProjectStore(baseDir: baseDir)
        store.projects = [
            Project(
                title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: sourceDir.path)]
            )
        ]
        return ProjectBrowserViewModel(store: store)
    }

    @Test("Reindexing a codebase records a fingerprint and reads as fresh")
    func reindexRecordsFingerprintAndIsFresh() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        try "class Widget {}\n".write(
            to: sourceDir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)

        let codebaseID = UUID()
        let model = makeModel(sourceDir: sourceDir, baseDir: baseDir, codebaseID: codebaseID)

        await model.editing.reindex(codebaseID: codebaseID)
        #expect(model.codebase(for: codebaseID)?.indexedFingerprint != nil)

        await model.ensureFreshnessLoaded(codebaseID: codebaseID)
        #expect(model.freshness(for: codebaseID) == .fresh)
    }

    @Test("Editing a file after reindexing reads as stale")
    func editingAfterReindexIsStale() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let file = sourceDir.appendingPathComponent("Widget.swift")
        try "class Widget {}\n".write(to: file, atomically: true, encoding: .utf8)

        let codebaseID = UUID()
        let model = makeModel(sourceDir: sourceDir, baseDir: baseDir, codebaseID: codebaseID)

        await model.editing.reindex(codebaseID: codebaseID)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        try "class Widget { var x = 1 }\n".write(to: file, atomically: true, encoding: .utf8)

        await model.ensureFreshnessLoaded(codebaseID: codebaseID)
        #expect(model.freshness(for: codebaseID) == .stale)
    }

    @Test("A codebase with no stored fingerprint reads as unknown, never falsely fresh or stale")
    func noStoredFingerprintIsUnknown() async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let codebaseID = UUID()
        let model = makeModel(sourceDir: sourceDir, baseDir: baseDir, codebaseID: codebaseID)

        await model.ensureFreshnessLoaded(codebaseID: codebaseID)
        #expect(model.freshness(for: codebaseID) == nil)
    }
}
