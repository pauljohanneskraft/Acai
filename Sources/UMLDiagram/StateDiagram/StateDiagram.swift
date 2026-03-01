/// A UML state diagram (statechart) model: states and the transitions between them.
public struct StateDiagram: Codable, Hashable, Sendable {

    // MARK: - State

    /// A configuration the system can occupy.
    public struct State: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case initial    /// Filled black circle – entry point
            case normal     /// Rounded rectangle
            case final      /// Circle within a circle – terminal state
            case choice     /// Diamond – dynamic branch point
            case fork       /// Thick horizontal bar – splits into concurrent regions
            case join       /// Thick horizontal bar – merges concurrent regions
            case composite  /// Contains nested sub-states
        }

        public var id: String
        public var name: String
        public var kind: Kind
        public var entryAction: String?
        public var exitAction: String?
        public var doActivity: String?
        /// Sub-states, populated only when `kind == .composite`.
        public var substates: [State]

        public init(
            id: String,
            name: String,
            kind: Kind = .normal,
            entryAction: String? = nil,
            exitAction: String? = nil,
            doActivity: String? = nil,
            substates: [State] = []
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.entryAction = entryAction
            self.exitAction = exitAction
            self.doActivity = doActivity
            self.substates = substates
        }
    }

    // MARK: - Transition

    /// A directed edge triggered by an event, optionally guarded and producing an action.
    public struct Transition: Codable, Hashable, Sendable {
        public var from: String   // state id
        public var to: String     // state id
        /// The triggering event (shown before the guard).
        public var event: String?
        /// Boolean condition in `[brackets]`.
        public var guardCondition: String?
        /// Behaviour executed during the transition (shown after `/`).
        public var action: String?

        public init(
            from: String,
            to: String,
            event: String? = nil,
            guardCondition: String? = nil,
            action: String? = nil
        ) {
            self.from = from
            self.to = to
            self.event = event
            self.guardCondition = guardCondition
            self.action = action
        }

        /// Formats the transition label as `event [guard] / action` per UML notation.
        public var label: String? {
            var parts: [String] = []
            if let e = event { parts.append(e) }
            if let g = guardCondition { parts.append("[\(g)]") }
            if let a = action { parts.append("/ \(a)") }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    // MARK: - Diagram

    public var title: String?
    public var states: [State]
    public var transitions: [Transition]

    public init(
        title: String? = nil,
        states: [State] = [],
        transitions: [Transition] = []
    ) {
        self.title = title
        self.states = states
        self.transitions = transitions
    }
}
