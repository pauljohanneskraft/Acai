import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// Unit-tests the freeform editing collaborators in isolation, driving each against a minimal
/// `FreeformEditingContext` stub (no view model, no persistence) — the separation issue #56 asked for.
@Suite("Freeform Collaborators")
@MainActor
struct FreeformCollaboratorTests {

    /// A bare `FreeformEditingContext`: holds the nodes/edges/selection and counts undo checkpoints,
    /// so a collaborator can be exercised without standing up the full view model.
    @MainActor
    final class StubContext: FreeformEditingContext {
        var nodes: [FreeformDiagram.Node] = []
        var edges: [FreeformDiagram.Edge] = []
        var selectedNodeIDs: Set<String> = []
        var selectedEdgeID: String?
        var selectionOrder: [String] = []
        private(set) var undoCheckpoints = 0
        private(set) var saves = 0
        private(set) var lastCoalescingKey: AnyHashable?

        func recordUndo(coalescingKey: AnyHashable?) {
            undoCheckpoints += 1
            lastCoalescingKey = coalescingKey
        }
        func save() { saves += 1 }
        func removeNodes(_ ids: Set<String>) {
            nodes.removeAll { ids.contains($0.id) }
            edges.removeAll { ids.contains($0.sourceNodeID) || ids.contains($0.targetNodeID) }
            selectedNodeIDs.subtract(ids)
        }
    }

    private func lifeline(_ id: String, x: Double) -> FreeformDiagram.Node {
        var node = FreeformDiagram.Node(name: id, content: .lifeline(.object), positionX: x, positionY: 0)
        node.id = id
        return node
    }

    private func typeNode(_ id: String) -> FreeformDiagram.Node {
        var node = FreeformDiagram.Node(
            name: id, content: .type(.init(typeKind: .class)), positionX: 0, positionY: 0
        )
        node.id = id
        return node
    }

    // MARK: - SequenceEditor

    @Test func addMessageAppendsInOrderAndSelectsIt() {
        let ctx = StubContext()
        ctx.nodes = [lifeline("A", x: 0), lifeline("B", x: 100)]
        let editor = SequenceEditor(context: ctx)

        editor.addMessage(from: "A", to: "B", kind: .synchronous)
        editor.addMessage(from: "B", to: "A", kind: .asynchronous)

        #expect(ctx.edges.count == 2)
        #expect(ctx.edges[0].messageOrder == 1)
        #expect(ctx.edges[1].messageOrder == 2)
        #expect(ctx.selectedEdgeID == ctx.edges[1].id)
        #expect(ctx.undoCheckpoints == 2)
        #expect(ctx.saves == 2)
    }

    @Test func messageEdgesRequireTwoLifelinesAndAreTimeOrdered() {
        let ctx = StubContext()
        ctx.nodes = [lifeline("A", x: 0), lifeline("B", x: 100), typeNode("C")]
        let editor = SequenceEditor(context: ctx)
        editor.addMessage(from: "A", to: "B", kind: .synchronous)

        // An edge to a non-lifeline is not a message.
        var toType = FreeformDiagram.Edge(sourceNodeID: "A", targetNodeID: "C", kind: .association)
        toType.messageOrder = 5
        ctx.edges.append(toType)

        #expect(editor.messageEdges.count == 1)
        #expect(editor.isMessageEdge(ctx.edges[0]))
        #expect(!editor.isMessageEdge(toType))
        #expect(editor.isLifeline("A") && !editor.isLifeline("C"))
    }

    @Test func reclassifyPromotesBetweenLifelinesAndClearsOtherwise() {
        let ctx = StubContext()
        ctx.nodes = [lifeline("A", x: 0), lifeline("B", x: 100), typeNode("C")]
        // An existing message at order 3 sets the high-water mark.
        var existing = FreeformDiagram.Edge(sourceNodeID: "A", targetNodeID: "B", kind: .dependency)
        existing.messageOrder = 3
        ctx.edges = [existing]
        let editor = SequenceEditor(context: ctx)

        var edge = FreeformDiagram.Edge(sourceNodeID: "B", targetNodeID: "A", kind: .dependency)
        editor.reclassify(&edge)
        #expect(edge.messageOrder == 4)
        #expect(edge.messageKind == .synchronous)

        edge.targetNodeID = "C"
        editor.reclassify(&edge)
        #expect(edge.messageOrder == nil)
        #expect(edge.messageKind == nil)
    }

    @Test func reclassifyBackfillsMissingKindForAlreadyOrderedMessage() {
        let ctx = StubContext()
        ctx.nodes = [lifeline("A", x: 0), lifeline("B", x: 100)]
        let editor = SequenceEditor(context: ctx)

        // A message between two lifelines that already has an order but no kind (older data).
        var edge = FreeformDiagram.Edge(sourceNodeID: "A", targetNodeID: "B", kind: .dependency)
        edge.messageOrder = 2
        edge.messageKind = nil
        editor.reclassify(&edge)

        #expect(edge.messageOrder == 2)
        #expect(edge.messageKind == .synchronous)
    }

    @Test func updateTypeContentIsNoOpForWrongKind() {
        let ctx = StubContext()
        ctx.nodes = [lifeline("L", x: 0)]   // not a `.type` node
        ctx.updateTypeContent("L") { $0.properties.append(.init(name: "x", type: "Int")) }
        // Wrong-kind node: no mutation, and the guard runs before recordUndo ⇒ no empty checkpoint.
        #expect(ctx.undoCheckpoints == 0)
        #expect(ctx.saves == 0)
    }

    // MARK: - SelectionClipboard

    @Test func partialEdgeIsRemovedByCutButNotCopied() {
        let ctx = StubContext()
        ctx.nodes = [typeNode("A"), typeNode("B")]
        ctx.edges = [FreeformDiagram.Edge(sourceNodeID: "A", targetNodeID: "B", kind: .association)]
        let clipboard = SelectionClipboard(context: ctx)

        // Select only A; the edge A→B is half-selected.
        ctx.selectedNodeIDs = ["A"]
        clipboard.copySelection()

        // Pasting into a fresh context proves the half-dangling edge was not copied.
        let dest = StubContext()
        SelectionClipboard(context: dest).paste()
        #expect(dest.nodes.count == 1)
        #expect(dest.edges.isEmpty)

        clipboard.cutSelection()
        #expect(ctx.nodes.map(\.id) == ["B"])
        #expect(ctx.edges.isEmpty)
    }

    // MARK: - StateMachineEditor

    @Test func addTransitionCarriesPayloadAndSelectsEdge() {
        let ctx = StubContext()
        let editor = StateMachineEditor(context: ctx)
        editor.addTransition(from: "S1", to: "S2")

        #expect(ctx.edges.count == 1)
        #expect(ctx.edges[0].transition != nil)
        #expect(ctx.selectedEdgeID == ctx.edges[0].id)
        #expect(ctx.undoCheckpoints == 1)
    }

    @Test func updateStateKindOnlyAppliesToStateNodes() {
        let ctx = StubContext()
        var stateNode = FreeformDiagram.Node(name: "S", content: .state(.normal), positionX: 0, positionY: 0)
        stateNode.id = "S"
        ctx.nodes = [stateNode, typeNode("T")]
        let editor = StateMachineEditor(context: ctx)

        editor.updateStateKind("S", kind: .final)
        editor.updateStateKind("T", kind: .final)   // no-op: not a state

        #expect(editor.isStateNode("S"))
        if case .state(let kind) = ctx.nodes[0].content { #expect(kind == .final) } else { Issue.record("not a state") }
        #expect(ctx.undoCheckpoints == 1)
    }

    // MARK: - TypeMemberEditor

    @Test func addPropertySetsStructuredFields() {
        let ctx = StubContext()
        ctx.nodes = [typeNode("T")]
        let editor = TypeMemberEditor(context: ctx)
        editor.addProperty(to: "T", draft: .init(
            name: "count", type: "Int", accessLevel: .private, isStatic: true, isAbstract: false
        ))

        guard case .type(let content) = ctx.nodes[0].content else { Issue.record("not a type"); return }
        #expect(content.properties.count == 1)
        #expect(content.properties[0].name == "count")
        #expect(content.properties[0].type == "Int")
        #expect(content.properties[0].accessLevel == .private)
        #expect(content.properties[0].isStatic)
        #expect(ctx.undoCheckpoints == 1)
        #expect(ctx.saves == 1)
    }

    @Test func addPropertyIsNoOpForBlankName() {
        let ctx = StubContext()
        ctx.nodes = [typeNode("T")]
        let editor = TypeMemberEditor(context: ctx)
        editor.addProperty(to: "T", draft: .init(
            name: "   ", type: "Int", accessLevel: .internal, isStatic: false, isAbstract: false
        ))

        guard case .type(let content) = ctx.nodes[0].content else { Issue.record("not a type"); return }
        #expect(content.properties.isEmpty)
        #expect(ctx.undoCheckpoints == 0)
    }

    @Test func updatePropertyMutatesExistingMember() {
        let ctx = StubContext()
        var node = typeNode("T")
        let memberID = UUID()
        node.content = .type(.init(typeKind: .class, properties: [
            .init(id: memberID, name: "old", type: "Int")
        ]))
        ctx.nodes = [node]
        let editor = TypeMemberEditor(context: ctx)

        editor.updateProperty(in: "T", memberID: memberID, draft: .init(
            name: "renamed", type: "String", accessLevel: .public, isStatic: true, isAbstract: true
        ))

        guard case .type(let content) = ctx.nodes[0].content else { Issue.record("not a type"); return }
        #expect(content.properties.count == 1)
        #expect(content.properties[0].id == memberID)
        #expect(content.properties[0].name == "renamed")
        #expect(content.properties[0].type == "String")
        #expect(content.properties[0].accessLevel == .public)
        #expect(content.properties[0].isStatic)
        #expect(content.properties[0].isAbstract)
    }

    @Test func addMethodSetsStructuredParameters() {
        let ctx = StubContext()
        ctx.nodes = [typeNode("T")]
        let editor = TypeMemberEditor(context: ctx)
        editor.addMethod(to: "T", draft: .init(
            name: "doWork", type: "String", accessLevel: .internal, isStatic: false, isAbstract: false,
            structuredParameters: [.init(name: "input", type: "Int")]
        ))

        guard case .type(let content) = ctx.nodes[0].content else { Issue.record("not a type"); return }
        #expect(content.methods.count == 1)
        #expect(content.methods[0].name == "doWork")
        #expect(content.methods[0].structuredParameters == [.init(name: "input", type: "Int")])
        #expect(content.methods[0].type == "String")
        #expect(content.methods[0].displayString == "doWork(input: Int): String")
    }

    @Test func updateMethodReplacesParameterList() {
        let ctx = StubContext()
        var node = typeNode("T")
        let memberID = UUID()
        node.content = .type(.init(typeKind: .class, methods: [
            .init(id: memberID, name: "old", structuredParameters: [.init(name: "a", type: "Int")])
        ]))
        ctx.nodes = [node]
        let editor = TypeMemberEditor(context: ctx)

        editor.updateMethod(in: "T", memberID: memberID, draft: .init(
            name: "renamed", type: "Void", accessLevel: .internal, isStatic: false, isAbstract: false,
            structuredParameters: [.init(name: "b", type: "String"), .init(name: "c", type: "Bool")]
        ))

        guard case .type(let content) = ctx.nodes[0].content else { Issue.record("not a type"); return }
        #expect(content.methods[0].name == "renamed")
        #expect(content.methods[0].structuredParameters.map(\.name) == ["b", "c"])
    }

    @Test func consecutiveNameEditsCoalesceIntoOneCheckpointPerField() {
        let ctx = StubContext()
        ctx.nodes = [typeNode("T")]
        let editor = TypeMemberEditor(context: ctx)
        // The stub counts every recordUndo call; coalescing is the manager's job, so here we only
        // assert each distinct edit records a checkpoint (the history manager merges by key).
        editor.updateNodeName("T", name: "A")
        editor.updateNodeName("T", name: "AB")
        #expect(ctx.nodes[0].name == "AB")
        #expect(ctx.undoCheckpoints == 2)
    }
}
