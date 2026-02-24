/// A UML use-case diagram model: actors, use cases, and the relationships between them.
public struct UseCaseDiagram: Codable, Hashable, Sendable {

    // MARK: - Actor

    /// A participant that interacts with the system (human user or external system).
    public struct Actor: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        /// When `true` the actor represents an external system rather than a human user.
        public var isSystem: Bool

        public init(id: String, name: String, isSystem: Bool = false) {
            self.id = id
            self.name = name
            self.isSystem = isSystem
        }
    }

    // MARK: - Use Case

    /// A behaviour offered by the system.
    public struct UseCase: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var description: String?

        public init(id: String, name: String, description: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
        }
    }

    // MARK: - Relationship

    /// A directed connection between actors and/or use cases.
    public struct Relationship: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            /// Actor participates in a use case (undirected association).
            case association
            /// Base use case always incorporates the behaviour of another (`<<include>>`).
            case include
            /// A use case conditionally extends another at an extension point (`<<extend>>`).
            case extend
            /// Inheritance between two actors or two use cases.
            case generalization
        }

        public var source: String
        public var target: String
        public var kind: Kind
        /// Optional condition / extension-point label (used with `.extend`).
        public var condition: String?

        public init(
            source: String,
            target: String,
            kind: Kind,
            condition: String? = nil
        ) {
            self.source = source
            self.target = target
            self.kind = kind
            self.condition = condition
        }
    }

    // MARK: - Diagram

    public var title: String?
    public var actors: [Actor]
    public var useCases: [UseCase]
    public var relationships: [Relationship]
    /// Optional label for the system-boundary box that surrounds the use cases.
    public var systemBoundaryLabel: String?

    public init(
        title: String? = nil,
        actors: [Actor] = [],
        useCases: [UseCase] = [],
        relationships: [Relationship] = [],
        systemBoundaryLabel: String? = nil
    ) {
        self.title = title
        self.actors = actors
        self.useCases = useCases
        self.relationships = relationships
        self.systemBoundaryLabel = systemBoundaryLabel
    }
}
