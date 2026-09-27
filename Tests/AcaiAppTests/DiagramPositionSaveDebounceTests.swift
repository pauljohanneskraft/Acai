import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiTestSupport
@testable import AcaiApp

/// Records every on-disk write while still producing the real file, so a test can tell one write
/// from three and still read back what landed.
private struct CountingDiagramWriter: GeneratedDiagramWriting {
    let writes: Locked<[Double]>

    func write(_ diagram: GeneratedDiagram, to url: URL) throws {
        writes.withValue { $0.append(diagram.canvasOffsetX) }
        try JSONEncoder().encode(diagram).write(to: url, options: .atomic)
    }
}

@Suite("Debounced diagram position saves")
@MainActor
struct DiagramPositionSaveDebounceTests {
    private static let debounce = Duration.milliseconds(50)

    private func makeModel(
        writes: Locked<[Double]>
    ) -> (model: ProjectBrowserViewModel, diagramID: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-debounce-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(
            baseDir: tempDir,
            analysisStore: AnalysisStore(directory: tempDir.appendingPathComponent("analysis-store")),
            diagramWriter: DebouncedDiagramWriter(
                debounce: Self.debounce, writer: CountingDiagramWriter(writes: writes))
        )
        let projectID = UUID()
        let codebaseID = UUID()
        store.projects = [
            Project(
                id: projectID, title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)]
            )
        ]
        let model = ProjectBrowserViewModel(store: store)
        let diagramID = model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram)
        return (model, diagramID!)
    }

    private func recenter(_ model: ProjectBrowserViewModel, _ diagramID: UUID, offsetX: CGFloat) {
        model.diagrams.updatePositions(
            diagramID: diagramID, positions: [:], scale: 1,
            offset: CGPoint(x: offsetX, y: 0), debounced: true
        )
    }

    /// The whole point of the debounce: the canvas transform reaches memory immediately, but nothing
    /// is encoded or written while the user is still stepping through matches.
    @Test func aSearchRecentringPerformsNoSynchronousWrite() throws {
        let writes = Locked<[Double]>([])
        let (model, diagramID) = makeModel(writes: writes)
        let writesAfterCreation = writes.value.count

        recenter(model, diagramID, offsetX: 111)

        #expect(writes.value.count == writesAfterCreation)
        #expect(model.store.generatedDiagrams[diagramID]?.canvasOffsetX == 111)
    }

    @Test func aBurstOfSearchRecentringsCollapsesToOneTrailingWrite() async throws {
        let writes = Locked<[Double]>([])
        let (model, diagramID) = makeModel(writes: writes)
        let writesAfterCreation = writes.value.count

        // No suspension point between them, so this is one burst: the first two schedules cannot
        // have reached their timer before the third replaced them.
        for offsetX in [CGFloat(10), 20, 30] {
            recenter(model, diagramID, offsetX: offsetX)
        }
        await model.store.diagramWriter.flush()

        #expect(writes.value.count == writesAfterCreation + 1)
        // The burst's *last* offset, not its first — the pending write reads the diagram when it
        // fires rather than capturing a snapshot when it was scheduled.
        #expect(writes.value.last == 30)
    }

    /// A drag commit, an undo or the canvas lifecycle still save synchronously. A pending debounced
    /// write firing afterwards would put the older transform back.
    @Test func aSynchronousSaveDropsAPendingDebouncedWrite() async throws {
        let writes = Locked<[Double]>([])
        let (model, diagramID) = makeModel(writes: writes)
        let writesAfterCreation = writes.value.count

        recenter(model, diagramID, offsetX: 10)
        model.diagrams.updatePositions(
            diagramID: diagramID, positions: [:], scale: 1, offset: CGPoint(x: 99, y: 0))
        await model.store.diagramWriter.flush()

        #expect(writes.value.count == writesAfterCreation + 1)
        #expect(writes.value.last == 99)
    }

    /// Deleting a diagram takes it out of the store, which is what the pending write reads — so the
    /// file stays gone without deletion needing to know the writer exists.
    @Test func deletingADiagramWithAPendingWriteLeavesItsFileDeleted() async throws {
        let writes = Locked<[Double]>([])
        let (model, diagramID) = makeModel(writes: writes)
        let url = model.store.generatedDiagramURL(diagramID)

        recenter(model, diagramID, offsetX: 10)
        let writesBeforeDeletion = writes.value.count
        model.diagrams.remove(diagramID)
        await model.store.diagramWriter.flush()

        #expect(writes.value.count == writesBeforeDeletion)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
