import UMLDiagram

/// The delta between two `StateDiagram` revisions (same variable, two codebase versions).
///
/// Transitions are identified by `(from, to, event)`; a guard/action change on the same trigger is
/// *changed*. States are identified by `id`. The `union` merges both revisions so a renderer can
/// draw every transition and tint it by `status(of:)`.
public struct StateDiagramDiff: Sendable {
    public let union: StateDiagram
    private let statusByKey: [String: DeltaStatus]

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

        // States: every state from both sides (new first, old-only appended).
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
}

extension StateDiagram.Transition {
    /// This transition's identity for diffing: `(from, to, event)`. A guard/action change on the
    /// same trigger is reported as *changed*, not add+remove.
    var diffKey: String {
        "\(from)\u{1}\(to)\u{1}\(event ?? "")"
    }
}
