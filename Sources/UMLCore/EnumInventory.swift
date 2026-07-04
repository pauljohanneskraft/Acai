/// The enum-case inventory of a codebase: every enum-like type with its cases, raw values and
/// associated-value shapes, each carrying its `SourceLocation` for a precise jump target. A value you
/// instantiate over an artifact (`EnumInventory(artifact:).entries`) — the read-only view the CLI's
/// `enums` command and downstream tooling render. Agnostic: it reads the parsed model and names no
/// language.
public struct EnumInventory: Sendable {
    /// One enum-like type and its declared cases.
    public struct Entry: Codable, Equatable, Sendable {
        public var type: String
        public var location: SourceLocation?
        public var cases: [Case]
    }

    /// One enum case, with its optional raw value and any associated-value parameters (rendered as
    /// `label: Type` or bare `Type`).
    public struct Case: Codable, Equatable, Sendable {
        public var name: String
        public var rawValue: String?
        public var associatedValues: [String]
    }

    private let artifact: CodeArtifact

    public init(artifact: CodeArtifact) {
        self.artifact = artifact
    }

    /// Every enum-like type (any type that declares cases), sorted by qualified name for deterministic
    /// output.
    public var entries: [Entry] {
        artifact.flattened()
            .filter { !$0.enumCases.isEmpty }
            .map { type in
                Entry(
                    type: type.qualifiedName,
                    location: type.location,
                    cases: type.enumCases.map { $0.inventoryDescription })
            }
            .sorted { $0.type < $1.type }
    }
}

extension EnumCase {
    /// This case rendered for the enum inventory: its name, raw value, and associated values as
    /// `label: Type` (or bare `Type` when unlabelled).
    var inventoryDescription: EnumInventory.Case {
        EnumInventory.Case(
            name: name,
            rawValue: rawValue,
            associatedValues: associatedValues.map { parameter in
                let type = parameter.type?.name ?? "_"
                let label = parameter.externalName ?? parameter.internalName
                return label.isEmpty || label == "_" ? type : "\(label): \(type)"
            })
    }
}
