import CoreGraphics
import Testing
@testable import UMLDiagram
@testable import UMLRender

@Suite("Sequence Layout Model")
struct SequenceLayoutModelTests {

    private func diagram() -> SequenceDiagram {
        SequenceDiagram(
            title: "T",
            participants: [
                .init(id: "A", name: "Alpha", kind: .object),
                .init(id: "B", name: "Beta", kind: .object),
                .init(id: "C", name: "Gamma", kind: .object)
            ],
            messages: [
                .init(from: "Alpha", to: "Beta", label: "one", kind: .synchronous, order: 0),
                .init(from: "Beta", to: "Gamma", label: "two", kind: .synchronous, order: 1)
            ]
        )
    }

    /// A full call/return pair: Alpha calls Beta, Beta returns.
    private func callReturnDiagram() -> SequenceDiagram {
        SequenceDiagram(
            participants: [
                .init(id: "A", name: "Alpha", kind: .object),
                .init(id: "B", name: "Beta", kind: .object)
            ],
            messages: [
                .init(from: "Alpha", to: "Beta", label: "work", kind: .synchronous, order: 0),
                .init(from: "Beta", to: "Alpha", label: nil, kind: .return, order: 1)
            ]
        )
    }

    @Test("Participants are placed left-to-right; messages stack top-to-bottom")
    func basicGeometry() {
        let layout = SequenceLayoutModel(diagram: diagram())

        let xs = layout.participants.map(\.lifelineX)
        #expect(xs == xs.sorted())
        #expect(Set(xs).count == 3)

        // Messages resolve by participant *name* and step downward by order. Arrow endpoints
        // sit on activation-bar edges, so they are near (within a bar width of) the lifelines.
        #expect(layout.messages.count == 2)
        #expect(layout.messages[0].y < layout.messages[1].y)
        let barWidth = SequenceLayoutModel.activationWidth
        #expect(abs(layout.messages[0].fromX - layout.participants[0].lifelineX) <= barWidth)
        #expect(abs(layout.messages[0].toX - layout.participants[1].lifelineX) <= barWidth)

        // Lifelines drop below the header row; content is non-empty.
        #expect(layout.participants[0].lifelineTop == SequenceLayoutModel.headerHeight)
        #expect(layout.contentSize.width > 0)
        #expect(layout.contentSize.height > SequenceLayoutModel.headerHeight)
    }

    @Test("A position override moves only that participant, not its neighbours")
    func overrideMovesOnlyOneParticipant() {
        let base = SequenceLayoutModel(diagram: diagram())
        let baseX = Dictionary(uniqueKeysWithValues: base.participants.map { ($0.id, $0.lifelineX) })

        let moved = SequenceLayoutModel(diagram: diagram(), positionOverrides: ["A": 900])
        let movedX = Dictionary(uniqueKeysWithValues: moved.participants.map { ($0.id, $0.lifelineX) })

        #expect(movedX["A"] == 900)
        #expect(movedX["B"] == baseX["B"])
        #expect(movedX["C"] == baseX["C"])
    }

    @Test("Self-calls are detected")
    func selfCall() {
        let selfDiagram = SequenceDiagram(
            participants: [.init(id: "A", name: "Alpha", kind: .object)],
            messages: [.init(from: "Alpha", to: "Alpha", label: "loop", kind: .synchronous, order: 0)]
        )
        let layout = SequenceLayoutModel(diagram: selfDiagram)
        #expect(layout.messages.count == 1)
        #expect(layout.messages[0].isSelf)
    }

    // MARK: - Execution occurrences

    @Test("A call/return pair produces an activation on the callee spanning call to return")
    func calleeActivationSpansCallToReturn() {
        let layout = SequenceLayoutModel(diagram: callReturnDiagram())
        let beta = layout.participants.first { $0.name == "Beta" }!

        // One bar on the callee, one root bar on the initiator.
        let betaBars = layout.activations.filter { $0.participantID == beta.id }
        #expect(betaBars.count == 1)
        let bar = betaBars[0]

        // The bar straddles the callee's lifeline and spans the call row to the return row.
        #expect(abs(bar.rect.midX - beta.lifelineX) < 0.5)
        let callY = layout.messages[0].y
        let returnY = layout.messages[1].y
        #expect(bar.rect.minY <= callY)
        #expect(bar.rect.maxY >= returnY)
    }

    @Test("The initiating participant gets a root activation for the whole interaction")
    func initiatorRootActivation() {
        let layout = SequenceLayoutModel(diagram: callReturnDiagram())
        let alpha = layout.participants.first { $0.name == "Alpha" }!

        let alphaBars = layout.activations.filter { $0.participantID == alpha.id }
        #expect(alphaBars.count == 1)
        // The root bar covers all messages.
        let bar = alphaBars[0]
        #expect(bar.rect.minY <= layout.messages.first!.y)
        #expect(bar.rect.maxY >= layout.messages.last!.y)
    }

    @Test("A nested self-call activation is offset from its parent bar")
    func nestedSelfCallActivationIsOffset() {
        let nested = SequenceDiagram(
            participants: [.init(id: "A", name: "Alpha", kind: .object)],
            messages: [
                .init(from: "Alpha", to: "Alpha", label: "step", kind: .synchronous, order: 0),
                .init(from: "Alpha", to: "Alpha", label: nil, kind: .return, order: 1)
            ]
        )
        let layout = SequenceLayoutModel(diagram: nested)
        let bars = layout.activations
        #expect(bars.count == 2)  // root + nested
        let centres = Set(bars.map(\.rect.midX))
        #expect(centres.count == 2)  // nested bar is horizontally offset from the root
    }

    // MARK: - Combined fragments

    @Test("A loop fragment frames the rows of its covered messages across involved lifelines")
    func loopFragmentFramesCoveredRows() {
        var d = diagram()
        d.fragments = [.init(kind: .loop, operands: [
            .init(guardLabel: "more items", firstOrder: 0, lastOrder: 1)
        ])]
        let layout = SequenceLayoutModel(diagram: d)

        #expect(layout.fragments.count == 1)
        let frame = layout.fragments[0]
        #expect(frame.kind == .loop)
        // Vertically spans both message rows.
        #expect(frame.rect.minY < layout.messages[0].y)
        #expect(frame.rect.maxY > layout.messages[1].y)
        // Horizontally spans all three involved lifelines.
        let xs = layout.participants.map(\.lifelineX)
        #expect(frame.rect.minX < xs.min()!)
        #expect(frame.rect.maxX > xs.max()!)
        // The guard is rendered in brackets.
        #expect(frame.guards.map(\.label) == ["[more items]"])
        #expect(frame.separatorYs.isEmpty)
    }

    @Test("An alt fragment draws a separator between its operands")
    func altFragmentSeparatesOperands() {
        var d = diagram()
        d.fragments = [.init(kind: .alt, operands: [
            .init(guardLabel: "found", firstOrder: 0, lastOrder: 0),
            .init(guardLabel: "else", firstOrder: 1, lastOrder: 1)
        ])]
        let layout = SequenceLayoutModel(diagram: d)

        let frame = layout.fragments[0]
        #expect(frame.separatorYs.count == 1)
        // Separator falls between the two message rows.
        #expect(frame.separatorYs[0] > layout.messages[0].y)
        #expect(frame.separatorYs[0] < layout.messages[1].y)
        #expect(frame.guards.count == 2)
    }

    @Test("The operator tab tracks the operator name and sits at the frame's top-left")
    func fragmentTabTracksOperatorName() {
        func tabRect(_ kind: SequenceDiagram.Fragment.Kind) -> CGRect {
            var d = diagram()
            d.fragments = [.init(kind: kind, operands: [.init(firstOrder: 0, lastOrder: 1)])]
            return SequenceLayoutModel(diagram: d).fragments[0].tabRect
        }

        let alt = tabRect(.alt)
        let critical = tabRect(.critical)
        #expect(critical.width > alt.width)

        var d = diagram()
        d.fragments = [.init(kind: .critical, operands: [.init(firstOrder: 0, lastOrder: 1)])]
        let frame = SequenceLayoutModel(diagram: d).fragments[0]
        #expect(frame.tabRect.origin == frame.rect.origin)
    }

    @Test("A fragment covering no laid-out messages is dropped")
    func emptyFragmentIsDropped() {
        var d = diagram()
        d.fragments = [.init(kind: .opt, operands: [.init(firstOrder: 90, lastOrder: 99)])]
        let layout = SequenceLayoutModel(diagram: d)
        #expect(layout.fragments.isEmpty)
    }

    @Test("Arrow endpoints land on the activation-bar edges")
    func arrowEndpointsTouchBarEdges() {
        let layout = SequenceLayoutModel(diagram: callReturnDiagram())
        let alpha = layout.participants.first { $0.name == "Alpha" }!
        let beta = layout.participants.first { $0.name == "Beta" }!
        let half = SequenceLayoutModel.activationWidth / 2

        // Call: leaves Alpha's root bar right edge, arrives at Beta's bar left edge.
        let call = layout.messages[0]
        #expect(call.fromX == alpha.lifelineX + half)
        #expect(call.toX == beta.lifelineX - half)

        // Return: leaves Beta's bar left edge, arrives back at Alpha's bar right edge.
        let ret = layout.messages[1]
        #expect(ret.fromX == beta.lifelineX - half)
        #expect(ret.toX == alpha.lifelineX + half)
    }
}
