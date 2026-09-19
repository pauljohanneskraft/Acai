import Foundation
import Testing
@testable import AcaiApp

@Suite("Staging an export for the share sheet")
struct ExportStagingTests {
    private let staging = ExportStaging(
        root: FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-export-staging-\(UUID().uuidString)", isDirectory: true)
    )

    @Test func writesTheDataUnderItsOwnName() throws {
        let staged = try staging.stage(Data("digraph {}".utf8), as: "Widgets.txt")
        #expect(staged.fileURL.lastPathComponent == "Widgets.txt")
        #expect(try Data(contentsOf: staged.fileURL) == Data("digraph {}".utf8))
        staging.discardAll()
    }

    @Test func twoExportsOfTheSameNameDoNotCollide() throws {
        let first = try staging.stage(Data("a".utf8), as: "Diagram.png")
        let second = try staging.stage(Data("b".utf8), as: "Diagram.png")
        #expect(first.fileURL != second.fileURL)
        #expect(try Data(contentsOf: first.fileURL) == Data("a".utf8))
        staging.discardAll()
    }

    @Test func aSlashInTheNameStaysInsideTheStagingFolder() throws {
        let staged = try staging.stage(Data("x".utf8), as: "../Escape/Diagram.png")
        #expect(staged.fileURL.path.hasPrefix(staging.root.resolvingSymlinksInPath().path)
            || staged.fileURL.path.hasPrefix(staging.root.path))
        #expect(staged.fileURL.lastPathComponent == "..-Escape-Diagram.png")
        staging.discardAll()
    }

    @Test func discardAllRemovesEveryStagedFile() throws {
        let staged = try staging.stage(Data("x".utf8), as: "Diagram.png")
        staging.discardAll()
        #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    }
}
