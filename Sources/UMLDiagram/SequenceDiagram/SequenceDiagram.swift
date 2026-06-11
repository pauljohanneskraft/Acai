import Foundation

/// A UML sequence diagram model: participants and time-ordered messages between them.
public struct SequenceDiagram: Codable, Hashable, Sendable {

    // MARK: - Participant

    /// A lifeline in the sequence diagram.
    public struct Participant: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case actor       /// Human user
            case object      /// Plain object / instance
            case boundary    /// UI boundary object
            case control     /// Controller / use-case handler
            case entity      /// Persistent data entity
            case database    /// Data store

            /// UML stereotype label shown above the participant name (`nil` for plain objects).
            public var stereotype: String? {
                switch self {
                case .object:
                    nil
                case .actor:
                    "actor"
                case .boundary:
                    "boundary"
                case .control:
                    "control"
                case .entity:
                    "entity"
                case .database:
                    "database"
                }
            }
        }

        public var id: String
        public var name: String
        public var kind: Kind

        public init(id: String, name: String, kind: Kind = .object) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    // MARK: - Message

    /// A communication between two participants at a specific point in time.
    public struct Message: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case synchronous    /// Filled arrowhead – caller blocks until reply
            case asynchronous   /// Open arrowhead – fire and forget
            case `return`       /// Dashed line – response to a synchronous call
            case create         /// Object creation (`<<create>>`)
            case destroy        /// Object destruction (`<<destroy>>`)
        }

        public var from: String  // participant id
        public var to: String    // participant id
        public var label: String?
        public var kind: Kind
        /// Determines the top-to-bottom order in which this message is drawn.
        public var order: Int

        public init(
            from: String,
            to: String,
            label: String? = nil,
            kind: Kind = .synchronous,
            order: Int = 0
        ) {
            self.from = from
            self.to = to
            self.label = label
            self.kind = kind
            self.order = order
        }
    }

    // MARK: - Combined Fragment

    /// A UML 2 combined fragment: a frame around a group of messages executed under specific
    /// circumstances (`loop`, `alt`, `opt`, …). Each operand covers a contiguous span of
    /// message orders and may carry a guard condition; `alt` fragments have several operands,
    /// drawn with dashed separators between them.
    public struct Fragment: Codable, Hashable, Sendable, Identifiable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case alt        /// if…then…else — one operand per branch
            case opt        /// optional — executed only when the guard holds
            case loop       /// repeated while the guard holds
            case par        /// concurrent operands
            case `break`    /// alternative that replaces the rest of the interaction
            case critical   /// atomic region
        }

        /// One section of the fragment: a guard plus the message orders it covers (inclusive).
        public struct Operand: Codable, Hashable, Sendable {
            /// Guard condition shown in square brackets (e.g. `cartItem != null`), or `nil`.
            public var guardLabel: String?
            public var firstOrder: Int
            public var lastOrder: Int

            public init(guardLabel: String? = nil, firstOrder: Int, lastOrder: Int) {
                self.guardLabel = guardLabel
                self.firstOrder = firstOrder
                self.lastOrder = lastOrder
            }
        }

        public var id: String
        public var kind: Kind
        /// At least one; only `alt` and `par` meaningfully have several.
        public var operands: [Operand]

        public init(id: String = UUID().uuidString, kind: Kind, operands: [Operand]) {
            self.id = id
            self.kind = kind
            self.operands = operands
        }
    }

    // MARK: - Diagram

    public var title: String?
    public var participants: [Participant]
    public var messages: [Message]
    public var fragments: [Fragment]

    public init(
        title: String? = nil,
        participants: [Participant] = [],
        messages: [Message] = [],
        fragments: [Fragment] = []
    ) {
        self.title = title
        self.participants = participants
        self.messages = messages
        self.fragments = fragments
    }
}
