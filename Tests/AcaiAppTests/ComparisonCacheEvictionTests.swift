import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Gives every ref its own one-type artifact, so each `(directory, ref)` is a distinct cache entry.
private struct RefNamedComparisonSource: ComparisonArtifactSourcing, ComparisonArtifactProviding {
    var ref = ""

    func provider(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding {
        RefNamedComparisonSource(ref: ref)
    }

    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["\(ref).swift"]),
            types: [TypeDeclaration(id: ref, name: ref, qualifiedName: ref, kind: .class, accessLevel: .public)])
    }
}

private struct FailingComparisonSource: ComparisonArtifactSourcing, ComparisonArtifactProviding {
    struct Unreadable: Error {}

    func provider(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding { self }

    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) throws -> CodeArtifact {
        throw Unreadable()
    }
}

@Suite("Comparison cache eviction", .timeLimit(.minutes(1)))
@MainActor
struct ComparisonCacheEvictionTests {
    private let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("acai-comparison-cache-\(UUID().uuidString)", isDirectory: true)

    private func makeModel(
        checkouts: FakeCheckoutInspector = FakeCheckoutInspector(),
        sources: ComparisonArtifactSourcing = RefNamedComparisonSource()
    ) throws -> (ProjectBrowserViewModel, diagramID: UUID) {
        let store = ProjectStore(baseDir: baseDir)
        let model = ProjectBrowserViewModel(store: store, comparisonSources: sources, checkouts: checkouts)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        model.editing.addCodebase(to: projectID, name: "Demo", directoryURL: baseDir)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        model.selection = .generatedDiagram(diagramID)
        return (model, diagramID)
    }

    /// Picks `ref` as the diagram's comparison and loads its snapshot, the way the compare panel does.
    private func compare(_ model: ProjectBrowserViewModel, diagramID: UUID, against ref: String) async throws {
        model.updateComparisonGitRef(diagramID: diagramID, ref: ref)
        let diagram = try #require(model.generatedDiagram(for: diagramID))
        await model.ensureComparisonLoaded(for: diagram)
        _ = model.comparisonArtifact(for: diagram)
    }

    @Test func steppingThroughRevisionsEvictsTheOldestSnapshots() async throws {
        let (model, diagramID) = try makeModel()
        let capacity = model.comparisonRecency.capacity
        let refs = (1...capacity + 2).map { "r\($0)" }

        for ref in refs {
            try await compare(model, diagramID: diagramID, against: ref)
        }

        #expect(model.comparisonArtifacts.count == capacity)
        #expect(model.comparisonRecency.ordered.map(\.ref) == Array(refs.suffix(capacity)))
        // The comparison the diagram is showing is the newest, so it is still there.
        #expect(model.comparisonArtifact(for: try #require(model.generatedDiagram(for: diagramID))) != nil)
        for evicted in refs.prefix(2) {
            #expect(!model.comparisonArtifacts.keys.contains { $0.ref == evicted })
        }
    }

    @Test func anEvictedSnapshotIsDroppedWithItsDerivationsAndIsReloadableOnReturn() async throws {
        let (model, diagramID) = try makeModel()
        let capacity = model.comparisonRecency.capacity
        let first = "r1"
        for ref in (1...capacity + 1).map({ "r\($0)" }) {
            try await compare(model, diagramID: diagramID, against: ref)
            if ref == first {
                await model.ensureComparisonAnalysisLoaded(for: try #require(model.generatedDiagram(for: diagramID)))
            }
        }

        #expect(!model.comparisonDisplayCache.keys.contains { $0.ref == first })
        #expect(!model.comparisonAnalyses.keys.contains { $0.ref == first })

        // Going back to it reloads rather than showing an empty comparison.
        try await compare(model, diagramID: diagramID, against: first)
        let diagram = try #require(model.generatedDiagram(for: diagramID))
        #expect(model.comparisonArtifact(for: diagram)?.types.map(\.id) == [first])
        #expect(model.comparisonError == nil)
    }

    private func panelStatus(_ model: ProjectBrowserViewModel, diagramID: UUID) throws -> ComparePanelState.Status? {
        let diagram = try #require(model.generatedDiagram(for: diagramID))
        return ComparePanelState(
            comparisonGitRef: diagram.comparisonGitRef,
            comparisonBaseRef: diagram.comparisonBaseRef,
            hasOldArtifact: model.comparisonArtifact(for: diagram) != nil,
            hasNewArtifact: model.comparisonNewArtifact(for: diagram) != nil,
            error: model.comparisonError
        ).status
    }

    @Test func returningToADiagramWhoseComparisonWasEvictedShowsLoadingUntilItReloads() async throws {
        let (model, firstID) = try makeModel()
        let project = try #require(model.store.projects.first)
        let codebaseID = try #require(project.codebases.first?.id)
        let secondID = try #require(model.diagrams.add(to: project.id, codebaseID: codebaseID, content: .packageDiagram))
        try await compare(model, diagramID: firstID, against: "first")

        model.selection = .generatedDiagram(secondID)
        for ref in (1...model.comparisonRecency.capacity).map({ "r\($0)" }) {
            try await compare(model, diagramID: secondID, against: ref)
        }
        #expect(!model.comparisonArtifacts.keys.contains { $0.ref == "first" })

        model.selection = .generatedDiagram(firstID)
        #expect(try panelStatus(model, diagramID: firstID) == .loading)
        await model.ensureComparisonLoaded(for: try #require(model.generatedDiagram(for: firstID)))
        #expect(try panelStatus(model, diagramID: firstID) == .loaded)
    }

    @Test func memoryPressurePurgesEverySnapshotButTheOneOnScreen() async throws {
        let (model, diagramID) = try makeModel()
        try await compare(model, diagramID: diagramID, against: "old")
        try await compare(model, diagramID: diagramID, against: "current")
        #expect(model.comparisonArtifacts.count == 2)

        model.purgeCachesUnderMemoryPressure()

        #expect(model.comparisonArtifacts.keys.map(\.ref) == ["current"])
        #expect(model.comparisonRecency.ordered.map(\.ref) == ["current"])
    }

    @Test func aPullRequestComparisonKeepsBothItsSidesAndItsMergeBase() async throws {
        let (model, diagramID) = try makeModel(checkouts: FakeCheckoutInspector(mergeBase: "merge-base"))
        model.selectComparisonPullRequest(diagramID: diagramID, base: "main", head: "feature")
        await model.ensureComparisonLoaded(for: try #require(model.generatedDiagram(for: diagramID)))

        model.purgeCachesUnderMemoryPressure()

        #expect(model.comparisonArtifacts.keys.map(\.ref).sorted() == ["feature", "merge-base"])
        #expect(Array(model.resolvedMergeBases.values) == ["merge-base"])
    }

    @Test func mergeBasesStayBoundedWhenTheirSnapshotsFailToLoad() async throws {
        let (model, diagramID) = try makeModel(
            checkouts: FakeCheckoutInspector(mergeBase: "merge-base"), sources: FailingComparisonSource())
        let capacity = model.mergeBaseRecency.capacity

        for index in 0...capacity {
            model.selectComparisonPullRequest(diagramID: diagramID, base: "main", head: "feature-\(index)")
            await model.ensureComparisonLoaded(for: try #require(model.generatedDiagram(for: diagramID)))
        }

        #expect(model.comparisonError != nil)
        #expect(model.resolvedMergeBases.count == capacity)
        #expect(model.resolvedMergeBases.keys.contains { $0.head == "feature-\(capacity)" })
    }
}

@Suite("Display artifact cache under memory pressure")
@MainActor
struct DisplayArtifactCacheTests {
    private let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("acai-display-cache-\(UUID().uuidString)", isDirectory: true)

    private func makeModel(codebaseCount: Int) throws -> (ProjectBrowserViewModel, [UUID]) {
        let model = ProjectBrowserViewModel(store: ProjectStore(baseDir: baseDir))
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        for index in 0..<codebaseCount {
            model.editing.addCodebase(
                to: projectID, name: "C\(index)", directoryURL: baseDir.appendingPathComponent("c\(index)"))
        }
        let ids = try #require(model.store.projects.first?.codebases.map(\.id))
        for id in ids {
            model.store.artifacts[id] = CodeArtifact(
                metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
                types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public)])
        }
        return (model, ids)
    }

    // Quick Open reads every codebase's display artifact over an unrelated selection.
    @Test func readingManyCodebasesOffScreenKeepsEveryDerivation() throws {
        let (model, ids) = try makeModel(codebaseCount: 6)
        model.selection = nil

        for id in ids {
            _ = model.artifact(for: id)
        }

        #expect(Set(model.displayArtifactCache.keys) == Set(ids))
    }

    @Test func memoryPressureKeepsOnlyTheDisplayedCodebasesDerivation() throws {
        let (model, ids) = try makeModel(codebaseCount: 3)
        for id in ids {
            _ = model.artifact(for: id)
        }
        model.selection = .codebase(ids[1])

        model.purgeCachesUnderMemoryPressure()

        #expect(Array(model.displayArtifactCache.keys) == [ids[1]])
        #expect(model.artifact(for: ids[0]) != nil)
    }
}

@Suite("Recency order")
struct RecencyOrderTests {
    @Test func reusingAKeyMakesItTheNewest() {
        var order = RecencyOrder<String>(capacity: 2)
        for key in ["a", "b", "a", "c"] {
            order.use(key)
        }

        #expect(order.overflow(retaining: []) == ["b"])
        #expect(order.ordered == ["a", "c"])
    }

    @Test func aKeyInUseIsKeptEvenWhenItIsTheOldest() {
        var order = RecencyOrder<String>(capacity: 2)
        for key in ["a", "b", "c", "d"] {
            order.use(key)
        }

        #expect(order.overflow(retaining: ["a"]) == ["b", "c"])
        #expect(order.ordered == ["a", "d"])
    }

    @Test func aCacheStaysOverItsBoundRatherThanEvictingWhatIsInUse() {
        var order = RecencyOrder<String>(capacity: 1)
        for key in ["a", "b", "c"] {
            order.use(key)
        }

        #expect(order.overflow(retaining: ["a", "b", "c"]).isEmpty)
        #expect(order.ordered == ["a", "b", "c"])
    }

    @Test func aPurgeKeepsOnlyWhatIsInUse() {
        var order = RecencyOrder<String>(capacity: 4)
        for key in ["a", "b", "c"] {
            order.use(key)
        }

        #expect(order.purge(retaining: ["b"]) == ["a", "c"])
        #expect(order.ordered == ["b"])
    }
}
