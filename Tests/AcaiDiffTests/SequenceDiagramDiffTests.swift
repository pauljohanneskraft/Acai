import Testing
import AcaiDiagram
@testable import AcaiDiff

@Suite("Diff: SequenceDiagramDiff")
struct SequenceDiagramDiffTests {

    private typealias Participant = SequenceDiagram.Participant
    private typealias Message = SequenceDiagram.Message

    @Test func detectsAddedAndRemovedParticipants() {
        let old = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "B", name: "B")],
            messages: [])
        let new = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "C", name: "C")],
            messages: [])
        let diff = SequenceDiagramDiff(old: old, new: new)
        #expect(diff.status(ofParticipant: "A") == .unchanged)
        #expect(diff.status(ofParticipant: "C") == .added)
        #expect(diff.status(ofParticipant: "B") == .removed)
        // The union keeps every participant (both sides) so a removed one can still be drawn.
        #expect(diff.union.participants.map(\.id).sorted() == ["A", "B", "C"])
    }

    @Test func detectsAddedAndRemovedMessagesByKey() {
        let old = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "B", name: "B")],
            messages: [Message(from: "A", to: "B", label: "x", order: 0)])
        let new = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "B", name: "B")],
            messages: [Message(from: "A", to: "B", label: "y", order: 0)])
        let diff = SequenceDiagramDiff(old: old, new: new)
        #expect(diff.status(of: Message(from: "A", to: "B", label: "y", order: 0)) == .added)
        #expect(diff.status(of: Message(from: "A", to: "B", label: "x", order: 0)) == .removed)
        #expect(diff.union.messages.count == 2)
    }

    @Test func unchangedMessageKeepsItsStatus() {
        let shared = Message(from: "A", to: "B", label: "x", order: 0)
        let old = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "B", name: "B")],
            messages: [shared])
        let new = SequenceDiagram(
            participants: [Participant(id: "A", name: "A"), Participant(id: "B", name: "B")],
            messages: [shared])
        let diff = SequenceDiagramDiff(old: old, new: new)
        #expect(diff.status(of: shared) == .unchanged)
    }
}
