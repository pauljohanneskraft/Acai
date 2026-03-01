/// A UML deployment diagram model: infrastructure nodes, their hosted artifacts,
/// and the communication paths between nodes.
public struct DeploymentDiagram: Codable, Hashable, Sendable {

    // MARK: - Node

    /// A physical or logical computational resource.
    public struct Node: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case device                 /// Physical hardware (3-D box notation)
            case executionEnvironment   /// Software runtime (e.g. JVM, Docker container)
            case server                 /// Generic server node
        }

        public var id: String
        public var name: String
        public var kind: Kind
        /// Artifacts directly hosted on this node.
        public var artifacts: [Artifact]
        /// Nested nodes (e.g. execution environments inside a device).
        public var children: [Node]

        public init(
            id: String,
            name: String,
            kind: Kind = .server,
            artifacts: [Artifact] = [],
            children: [Node] = []
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.artifacts = artifacts
            self.children = children
        }
    }

    // MARK: - Artifact

    /// A physical piece of information used or produced by the software.
    public struct Artifact: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case executable
            case library
            case file
            case source
            case script
        }

        public var id: String
        public var name: String
        public var kind: Kind

        public init(id: String, name: String, kind: Kind = .executable) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    // MARK: - Communication Path

    /// A connection between two nodes (analogous to an association on the network level).
    public struct CommunicationPath: Codable, Hashable, Sendable {
        public var from: String  // node id
        public var to: String    // node id
        public var label: String?
        /// The protocol or technology used (e.g. "HTTPS", "JDBC").
        public var protocolName: String?

        public init(
            from: String,
            to: String,
            label: String? = nil,
            protocolName: String? = nil
        ) {
            self.from = from
            self.to = to
            self.label = label
            self.protocolName = protocolName
        }
    }

    // MARK: - Diagram

    public var title: String?
    public var nodes: [Node]
    public var communicationPaths: [CommunicationPath]

    public init(
        title: String? = nil,
        nodes: [Node] = [],
        communicationPaths: [CommunicationPath] = []
    ) {
        self.title = title
        self.nodes = nodes
        self.communicationPaths = communicationPaths
    }
}
