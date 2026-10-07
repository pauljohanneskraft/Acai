import Foundation
import Testing
import AcaiCore
import AcaiGit
@testable import AcaiApp

/// Hands every `(codebase, ref)` the same canned artifact, or throws when `artifact` is `nil`.
private struct CannedComparisonSource: ComparisonArtifactSourcing, ComparisonArtifactProviding {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "History is unavailable." }
    }

    var artifact: CodeArtifact?

    func provider(codebaseID: UUID, ref: String, directory: URL) -> ComparisonArtifactProviding { self }

    func artifact(analyzer: CodebaseAnalyzing, fileFilter: FileFilter?) throws -> CodeArtifact {
        guard let artifact else { throw Unavailable() }
        return artifact
    }
}

@Suite("Comparison view model", .timeLimit(.minutes(1)))
@MainActor
struct ComparisonViewModelTests {
    private let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("acai-comparison-vm-\(UUID().uuidString)", isDirectory: true)
    private let refs = [GitCheckout.Ref(name: "main", kind: .branch), GitCheckout.Ref(name: "v1", kind: .tag)]

    private let oldArtifact = CodeArtifact(
        metadata: .init(sourceLanguage: .swift, filePaths: ["Old.swift"]),
        types: [TypeDeclaration(id: "Old", name: "Old", qualifiedName: "Old", kind: .class, accessLevel: .public)])

    private func makeModel(
        comparisonSources: ComparisonArtifactSourcing = CannedComparisonSource(),
        checkouts: LocalCheckoutInspecting = FakeCheckoutInspector()
    ) throws -> (ProjectBrowserViewModel, codebaseID: UUID, diagramID: UUID) {
        let store = ProjectStore(baseDir: baseDir)
        let model = ProjectBrowserViewModel(store: store, comparisonSources: comparisonSources, checkouts: checkouts)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        model.editing.addCodebase(to: projectID, name: "Demo", directoryURL: baseDir)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        return (model, codebaseID, diagramID)
    }

    @Test func comparisonRefsComeFromTheCheckoutInspector() async throws {
        let (model, codebaseID, _) = try makeModel(checkouts: FakeCheckoutInspector(refs: refs, currentRef: "main"))

        #expect(try await model.comparisonRefs(codebaseID: codebaseID) == refs)
        #expect(try await model.comparisonRefs(codebaseID: UUID()).isEmpty)
    }

    @Test func aFolderOutsideAnyRepositoryOffersNoRefs() async throws {
        let (model, codebaseID, _) = try makeModel(checkouts: FakeCheckoutInspector())

        #expect(try await model.comparisonRefs(codebaseID: codebaseID).isEmpty)
    }

    @Test func anUnreadableRepositoryFailsRatherThanOfferingNoRefs() async throws {
        let (model, codebaseID, _) = try makeModel(checkouts: FakeCheckoutInspector(refsAreUnreadable: true))

        await #expect(throws: FakeCheckoutInspector.Unreadable.self) {
            _ = try await model.comparisonRefs(codebaseID: codebaseID)
        }
    }

    @Test func clearingTheComparisonRefDropsTheComparisonAndItsError() async throws {
        let (model, _, diagramID) = try makeModel(comparisonSources: CannedComparisonSource(artifact: oldArtifact))
        model.updateComparisonGitRef(diagramID: diagramID, ref: "main")
        var diagram = try #require(model.generatedDiagram(for: diagramID))
        await model.ensureComparisonLoaded(for: diagram)
        #expect(model.comparisonArtifact(for: diagram)?.types.map(\.id) == ["Old"])
        model.comparisonError = "History is unavailable."

        model.updateComparisonGitRef(diagramID: diagramID, ref: nil)

        diagram = try #require(model.generatedDiagram(for: diagramID))
        #expect(diagram.comparisonGitRef == nil)
        #expect(diagram.comparisonBaseRef == nil)
        #expect(model.comparisonArtifact(for: diagram) == nil)
        #expect(model.comparisonError == nil)
    }

    @Test func aFailedSnapshotLoadReportsItsError() async throws {
        let (model, _, diagramID) = try makeModel(comparisonSources: CannedComparisonSource(artifact: nil))
        model.updateComparisonGitRef(diagramID: diagramID, ref: "main")
        let diagram = try #require(model.generatedDiagram(for: diagramID))

        await model.ensureComparisonLoaded(for: diagram)

        #expect(model.comparisonArtifact(for: diagram) == nil)
        #expect(model.comparisonError == "History is unavailable.")
    }
}
