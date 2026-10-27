import CoreGraphics
import Testing
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

/// A comparison change re-derives a diagram in place instead of rebuilding its view, so the compare
/// panel presented over it survives. These cover what that path has to match about a view model
/// constructed fresh for the same comparison.
@Suite("Diagram comparison update", .timeLimit(.minutes(1)))
@MainActor
struct DiagramComparisonUpdateTests {

    private let codebase = Codebase(name: "App", directoryPath: "/tmp/app")

    private func type(_ name: String, calling callee: String? = nil) -> TypeDeclaration {
        let callSites = callee.map { [CallSite(receiver: .type($0), methodName: "work")] } ?? []
        return TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            members: [Member(name: "work", kind: .method, accessLevel: .internal, callSites: callSites)],
            location: SourceLocation(filePath: "Sources/Module\(name)/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ names: [String], calling: [String: String] = [:]) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
            types: names.map { type($0, calling: calling[$0]) })
    }

    // MARK: - Class diagram

    @Test func aClassDiagramEntersDeltaModeInPlace() {
        let old = artifact(["A", "Gone"])
        let new = artifact(["A", "Added"])
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new)
        #expect(!viewModel.isDeltaMode)
        #expect(Set(viewModel.nodes.map(\.id)) == ["A", "Added"])

        viewModel.nodePositions["A"] = CGPoint(x: 10, y: 20)
        viewModel.recordUndo()
        #expect(viewModel.canUndo)

        viewModel.updateComparison(artifact: new, comparison: old)

        #expect(viewModel.isDeltaMode)
        // The union keeps a type only the comparison revision had, so it can be tinted as removed.
        #expect(Set(viewModel.nodes.map(\.id)) == ["A", "Added", "Gone"])
        #expect(viewModel.nodePositions["Gone"] != nil)
        #expect(!viewModel.canUndo)
    }

    @Test func aClassDiagramLeavesDeltaModeInPlace() {
        let old = artifact(["A", "Gone"])
        let new = artifact(["A"])
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)
        #expect(viewModel.isDeltaMode)

        viewModel.updateComparison(artifact: new, comparison: nil)

        #expect(!viewModel.isDeltaMode)
        #expect(Set(viewModel.nodes.map(\.id)) == ["A"])
    }

    /// A pull-request comparison replaces the "new" side too, not only the revision compared against.
    @Test func aClassDiagramPicksUpANewWorkingTreeArtifact() {
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: artifact(["A"]))

        viewModel.updateComparison(artifact: artifact(["A", "B"]), comparison: nil)

        #expect(Set(viewModel.nodes.map(\.id)) == ["A", "B"])
        #expect(viewModel.typeDisplayNames.name(forID: "B") == "B")
    }

    // MARK: - Movement-only diagrams

    @Test func aCallGraphEntersDeltaModeInPlaceAndDropsDraggedPositions() {
        let old = artifact(["A", "B"], calling: ["A": "B"])
        let new = artifact(["A", "B"])
        let viewModel = CallGraphViewModel(artifact: new, scope: .wholeCodebase)
        #expect(!viewModel.isDeltaMode)

        viewModel.positionOverrides["A.work"] = CGPoint(x: 5, y: 5)
        viewModel.recordUndo()
        #expect(viewModel.canUndo)

        viewModel.updateComparison(artifact: new, comparison: old)

        #expect(viewModel.isDeltaMode)
        #expect(viewModel.positionOverrides.isEmpty)
        #expect(!viewModel.canUndo)
    }

    @Test func aPackageDiagramEntersDeltaModeInPlaceAndDropsDraggedPositions() {
        let viewModel = PackageDiagramViewModel(artifact: artifact(["A", "B"]))
        #expect(!viewModel.isDeltaMode)

        viewModel.positionOverrides["ModuleA"] = CGPoint(x: 5, y: 5)
        viewModel.recordUndo()
        #expect(viewModel.canUndo)

        viewModel.updateComparison(artifact: artifact(["A", "B"]), comparison: artifact(["A"]))

        #expect(viewModel.isDeltaMode)
        #expect(viewModel.positionOverrides.isEmpty)
        #expect(!viewModel.canUndo)
    }
}
