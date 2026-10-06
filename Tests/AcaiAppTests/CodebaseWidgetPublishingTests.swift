import Foundation
import Synchronization
import Testing
@testable import AcaiApp

@Suite("Publishing codebase state to the widget (issue #218)", .timeLimit(.minutes(1)))
@MainActor
struct CodebaseWidgetPublishingTests {
    private let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let codebaseID = UUID()

    private func makeIndexedModel() async throws -> ProjectBrowserViewModel {
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "class Widget {}\nclass Gadget {}\n".write(
            to: sourceDir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        let store = ProjectStore(baseDir: baseDir.appendingPathComponent("store"))
        store.projects = [
            Project(
                title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: sourceDir.path)])
        ]
        let model = ProjectBrowserViewModel(store: store)
        await model.editing.reindex(codebaseID: codebaseID)
        await model.ensureAnalysisLoaded(codebaseID: codebaseID)
        await model.ensureFreshnessLoaded(codebaseID: codebaseID)
        return model
    }

    @Test("A test store over an explicit directory never writes the real App Group container")
    func explicitStoreHasNoPublisher() {
        defer { try? FileManager.default.removeItem(at: baseDir) }
        #expect(ProjectStore(baseDir: baseDir).widgetPublisher == nil)
    }

    @Test("Once analysed and checked, a codebase's inputs carry its analysis and freshness")
    func inputsCarryCurrentState() async throws {
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let model = try await makeIndexedModel()

        let input = try #require(model.widgetInputs().first)
        #expect(input.snapshot.analysedAt == model.codebase(for: codebaseID)?.lastIndexed)
        #expect(input.analysis != nil)
        #expect(input.snapshot.freshnessCheckedAt != nil)
        #expect(input.snapshot.isOutOfDate == false)
    }

    @Test("Right after a reindex, the previous analysis's counts and freshness aren't published as the new one's")
    func reindexDropsPreviousState() async throws {
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let model = try await makeIndexedModel()

        await model.editing.reindex(codebaseID: codebaseID)

        let input = try #require(model.widgetInputs().first)
        #expect(input.analysis == nil)
        #expect(input.snapshot.freshnessCheckedAt == nil)
        #expect(model.freshness(for: codebaseID) == nil)
    }

    @Test("Publishing writes the counts, and an unchanged publish doesn't spend a timeline reload")
    func publishWritesCountsOnce() async throws {
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let model = try await makeIndexedModel()
        let snapshotStore = CodebaseWidgetSnapshotStore(containerURL: baseDir.appendingPathComponent("group"))
        let reloads = Mutex(0)
        let publisher = CodebaseWidgetPublisher(store: snapshotStore) { reloads.withLock { $0 += 1 } }

        await publisher.publish(model.widgetInputs())
        await publisher.publish(model.widgetInputs())

        let published = try #require(snapshotStore.load().snapshot(for: codebaseID))
        #expect(published.typeCount == 2)
        #expect(published.findingCount != nil)
        #expect(published.freshnessCheckedAt != nil)
        #expect(reloads.withLock { $0 } == 1)
    }
}
