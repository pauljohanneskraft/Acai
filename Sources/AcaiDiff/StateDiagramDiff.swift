import AcaiDiagram

/// The delta between two `StateDiagram` revisions (same variable, two codebase versions).
///
/// Transitions are identified by `(from, to, event)`; a guard/action change on the same trigger is
/// *changed*. States are identified by `id`.
public struct StateDiagramDiff: Sendable {
    public let union: StateDiagram
    private let statusByKey: [String: DeltaStatus]
    private let stateStatusByID: [String: DeltaStatus]

    public init(old: StateDiagram, new: StateDiagram) {
        let oldByKey = Dictionary(old.transitions.map { ($0.diffKey, $0) }, uniquingKeysWith: { first, _ in first })
        let newByKey = Dictionary(new.transitions.map { ($0.diffKey, $0) }, uniquingKeysWith: { first, _ in first })

        var statusByKey: [String: DeltaStatus] = [:]
        for (key, transition) in newByKey {
            if let before = oldByKey[key] {
                statusByKey[key] = (before.label == transition.label) ? .unchanged : .changed
            } else {
                statusByKey[key] = .added
            }
        }
        let removed = old.transitions.filter { newByKey[$0.diffKey] == nil }
        for transition in removed { statusByKey[transition.diffKey] = .removed }
        self.statusByKey = statusByKey

        let oldStateIDs = Set(old.states.map(\.id))
        let newStateIDs = Set(new.states.map(\.id))
        var stateStatusByID: [String: DeltaStatus] = [:]
        for id in newStateIDs { stateStatusByID[id] = oldStateIDs.contains(id) ? .unchanged : .added }
        for id in oldStateIDs where !newStateIDs.contains(id) { stateStatusByID[id] = .removed }
        self.stateStatusByID = stateStatusByID

        var states = new.states
        let seenStates = Set(new.states.map(\.id))
        states += old.states.filter { !seenStates.contains($0.id) }

        self.union = StateDiagram(
            title: new.title ?? old.title,
            states: states,
            transitions: new.transitions + removed
        )
    }

    public func status(of transition: StateDiagram.Transition) -> DeltaStatus {
        statusByKey[transition.diffKey] ?? .unchanged
    }

    public func status(ofState id: String) -> DeltaStatus {
        stateStatusByID[id] ?? .unchanged
    }
}

extension StateDiagram.Transition {
    var diffKey: String {
        "\(from)\u{1}\(to)\u{1}\(event ?? "")"
    }
}
