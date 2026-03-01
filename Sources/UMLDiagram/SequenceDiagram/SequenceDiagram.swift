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

    // MARK: - Diagram

    public var title: String?
    public var participants: [Participant]
    public var messages: [Message]

    public init(
        title: String? = nil,
        participants: [Participant] = [],
        messages: [Message] = []
    ) {
        self.title = title
        self.participants = participants
        self.messages = messages
    }
}
