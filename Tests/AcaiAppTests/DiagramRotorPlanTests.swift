import CoreGraphics
import Testing
import AcaiCore
import AcaiDiff
@testable import AcaiApp

@Suite("Diagram rotor plan")
struct DiagramRotorPlanTests {

    private func element(
        _ id: String, x: CGFloat, y: CGFloat, height: CGFloat = 40, delta: DeltaStatus? = nil
    ) -> DiagramRotorPlan.Element {
        DiagramRotorPlan.Element(id: id, label: id, delta: delta, frame: CGRect(x: x, y: y, width: 80, height: height))
    }

    private func connection(
        _ id: String, x: CGFloat, y: CGFloat, delta: DeltaStatus? = nil
    ) -> DiagramRotorPlan.Element {
        DiagramRotorPlan.Element(connection: id, label: id, delta: delta, midpoint: CGPoint(x: x, y: y))
    }

    @Test("Elements read in rows, top to bottom and leading to trailing")
    func readingOrderFollowsRowsThenColumns() {
        let plan = DiagramRotorPlan(elements: [
            element("bottomRight", x: 400, y: 500),
            element("topRight", x: 400, y: 100),
            element("bottomLeft", x: 10, y: 500),
            element("topLeft", x: 10, y: 100)
        ])

        #expect(plan.elements.map(\.id) == ["topLeft", "topRight", "bottomLeft", "bottomRight"])
    }

    @Test("A top-aligned layer of boxes with different heights reads as one row")
    func topAlignedBoxesShareARow() {
        let plan = DiagramRotorPlan(elements: [
            element("right", x: 300, y: 100, height: 40),
            element("left", x: 100, y: 100, height: 300),
            element("nextRow", x: 10, y: 500)
        ])

        #expect(plan.elements.map(\.id) == ["left", "right", "nextRow"])
    }

    @Test("A centre-aligned layer of boxes with different heights reads as one row")
    func centreAlignedBoxesShareARow() {
        let plan = DiagramRotorPlan(elements: [
            element("short", x: 100, y: 230, height: 40),
            element("tall", x: 300, y: 100, height: 300),
            element("nextRow", x: 10, y: 500)
        ])

        #expect(plan.elements.map(\.id) == ["short", "tall", "nextRow"])
    }

    @Test("A box starting below the centre of the row's topmost box starts a new row")
    func aLowerBoxStartsItsOwnRow() {
        let plan = DiagramRotorPlan(elements: [element("below", x: 10, y: 130), element("above", x: 500, y: 100)])

        #expect(plan.elements.map(\.id) == ["above", "below"])
    }

    @Test("Connections read in their own order, after every element")
    func connectionsFollowTheElements() {
        let plan = DiagramRotorPlan(
            elements: [element("lower", x: 10, y: 500), element("upper", x: 10, y: 100)],
            connections: [connection("late", x: 50, y: 400), connection("early", x: 50, y: 20)]
        )

        #expect(plan.connections.map(\.id) == ["early", "late"])
        let order = ["upper", "lower", "early", "late"].map { plan.sortPriority(of: $0) }
        #expect(order == order.sorted(by: >))
    }

    @Test("Every element and connection sorts behind the chrome at the default priority")
    func everythingSortsBelowTheDefault() {
        let plan = DiagramRotorPlan(
            elements: [element("a", x: 10, y: 10), element("b", x: 200, y: 10)],
            connections: [connection("ab", x: 100, y: 30)]
        )

        #expect(["a", "b", "ab"].allSatisfy { plan.sortPriority(of: $0) < 0 })
        #expect(plan.sortPriority(of: "absent") == 0)
    }

    @Test("The changed rotor carries changed elements, then changed connections, each in reading order")
    func changedKeepsReadingOrder() {
        let plan = DiagramRotorPlan(
            elements: [
                element("removed", x: 300, y: 100, delta: .removed),
                element("untouched", x: 200, y: 100, delta: .unchanged),
                element("added", x: 100, y: 100, delta: .added),
                element("noComparison", x: 400, y: 100),
                element("edited", x: 500, y: 100, delta: .changed)
            ],
            connections: [
                connection("addedLink", x: 50, y: 300, delta: .added),
                connection("keptLink", x: 50, y: 200, delta: .unchanged)
            ]
        )

        #expect(plan.changed.map(\.id) == ["added", "removed", "edited", "addedLink"])
    }

    @Test("Two elements at the same point order by id rather than by how they were handed over")
    func coincidentElementsOrderDeterministically() {
        let forward = DiagramRotorPlan(elements: [element("a", x: 10, y: 10), element("b", x: 10, y: 10)])
        let reversed = DiagramRotorPlan(elements: [element("b", x: 10, y: 10), element("a", x: 10, y: 10)])

        #expect(forward.elements.map(\.id) == ["a", "b"])
        #expect(reversed.elements.map(\.id) == ["a", "b"])
    }
}

@Suite("Diagram rotor plan of a class diagram")
@MainActor
struct ClassDiagramRotorPlanTests {

    private func type(_ name: String) -> TypeDeclaration {
        TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
                        location: SourceLocation(filePath: "Sources/App/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
                     types: types, relationships: rels)
    }

    @Test("Type boxes read where they are drawn, and every relationship is a connection")
    func typeBoxesFollowTheirPositions() {
        let viewModel = ClassDiagramViewModel(
            codebase: Codebase(name: "App", directoryPath: "/tmp/app"),
            artifact: artifact([type("A"), type("B"), type("C")], [
                Relationship(kind: .dependency, source: "A", target: "B"),
                Relationship(kind: .inheritance, source: "C", target: "A")
            ])
        )
        viewModel.moveNode("C", to: CGPoint(x: 100, y: 100))
        viewModel.moveNode("A", to: CGPoint(x: 400, y: 100))
        viewModel.moveNode("B", to: CGPoint(x: 100, y: 600))

        let plan = viewModel.rotorPlan

        #expect(plan.elements.map(\.id) == ["C", "A", "B"])
        #expect(Set(plan.connections.map(\.id)) == Set(viewModel.edges.map(\.rotorID)))
        #expect(plan.connections.count == 2)
    }

    @Test("A comparison's added and removed relationships join the changed rotor; kept ones don't")
    func changedRelationshipsAreInTheChangedRotor() {
        let old = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "D")
        ])
        let new = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "C")
        ])
        let viewModel = ClassDiagramViewModel(
            codebase: Codebase(name: "App", directoryPath: "/tmp/app"), artifact: new, comparisonArtifact: old
        )
        func rotorID(_ source: String, _ target: String) -> String? {
            viewModel.edges.first { $0.sourceID == source && $0.targetID == target }?.rotorID
        }

        let changed = Set(viewModel.rotorPlan.changed.map(\.id))

        #expect(rotorID("A", "C").map(changed.contains) == true)
        #expect(rotorID("A", "D").map(changed.contains) == true)
        #expect(rotorID("A", "B").map(changed.contains) == false)
    }
}

@Suite("Diagram rotor plan of a freeform diagram")
@MainActor
struct FreeformDiagramRotorPlanTests {

    @Test("Lifelines read on the header row they are drawn on; messages and relationships are connections")
    func lifelinesReadOnTheHeaderRow() throws {
        let viewModel = FreeformDiagramViewModel()
        viewModel.addNode(kind: .lifeline, name: "A", at: CGPoint(x: 300, y: 0))
        viewModel.addNode(kind: .type(.class), name: "C", at: CGPoint(x: 10, y: 300))
        viewModel.addNode(kind: .lifeline, name: "B", at: CGPoint(x: 500, y: 900))
        let ids = viewModel.nodes.map(\.id)
        viewModel.addEdge(from: ids[0], to: ids[2], kind: .dependency)
        viewModel.addEdge(from: ids[0], to: ids[1], kind: .dependency)
        let layout = try #require(viewModel.sequence.sequenceLayout)

        let plan = viewModel.rotorPlan(sequenceLayout: layout)

        #expect(plan.elements.map(\.label) == ["A", "B", "C"])
        let relationship = try #require(viewModel.edges.first { !viewModel.sequence.isMessageEdge($0) })
        let expected = Set(layout.messages.map(\.freeformRotorID) + [relationship.rotorID])
        #expect(Set(plan.connections.map(\.id)) == expected)
        #expect(layout.messages.count == 1)
    }
}
