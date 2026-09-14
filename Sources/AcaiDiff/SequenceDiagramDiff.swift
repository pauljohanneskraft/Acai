import AcaiDiagram

/// The delta between two `SequenceDiagram` revisions (same entry point, two codebase versions).
///
/// Messages are identified by `(from, to, label, kind)` — `order` is layout only — so a message
/// present in both revisions is *unchanged* regardless of where it falls in the trace.
public struct SequenceDiagramDiff: Sendable {
    public let union: SequenceDiagram
    private let statusByKey: [String: DeltaStatus]
    private let participantStatusByID: [String: DeltaStatus]

    public init(old: SequenceDiagram, new: SequenceDiagram) {
        let oldKeys = Set(old.messages.map(\.diffKey))
        let newKeys = Set(new.messages.map(\.diffKey))

        var statusByKey: [String: DeltaStatus] = [:]
        for message in new.messages {
            statusByKey[message.diffKey] = oldKeys.contains(message.diffKey) ? .unchanged : .added
        }
        let removed = old.messages.filter { !newKeys.contains($0.diffKey) }
        for message in removed { statusByKey[message.diffKey] = .removed }
        self.statusByKey = statusByKey

        let oldParticipantIDs = Set(old.participants.map(\.id))
        let newParticipantIDs = Set(new.participants.map(\.id))
        var participantStatusByID: [String: DeltaStatus] = [:]
        for id in newParticipantIDs {
            participantStatusByID[id] = oldParticipantIDs.contains(id) ? .unchanged : .added
        }
        for id in oldParticipantIDs where !newParticipantIDs.contains(id) {
            participantStatusByID[id] = .removed
        }
        self.participantStatusByID = participantStatusByID

        var participants = new.participants
        let seenParticipants = Set(new.participants.map(\.id))
        participants += old.participants.filter { !seenParticipants.contains($0.id) }

        // order is reassigned below so the renderer lays messages out in this sequence.
        var messages = new.messages.sorted { $0.order < $1.order }
        messages += removed.sorted { $0.order < $1.order }
        for index in messages.indices { messages[index].order = index }

        self.union = SequenceDiagram(
            title: new.title ?? old.title,
            participants: participants,
            messages: messages,
            fragments: new.fragments
        )
    }

    public func status(of message: SequenceDiagram.Message) -> DeltaStatus {
        statusByKey[message.diffKey] ?? .unchanged
    }

    public func status(ofParticipant id: String) -> DeltaStatus {
        participantStatusByID[id] ?? .unchanged
    }
}

extension SequenceDiagram.Message {
    /// `order` is excluded — it's layout only.
    var diffKey: String {
        "\(from)\u{1}\(to)\u{1}\(label ?? "")\u{1}\(String(describing: kind))"
    }
}
