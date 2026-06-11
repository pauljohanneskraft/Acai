import UMLCore

/// Describes how a sequence diagram is traced from a codebase: the starting method, how deep
/// to follow calls, and how abstract receiver types resolve to concrete ones. The counterpart
/// of `ClassDiagramConfiguration` for sequence diagrams; lives next to the generator it
/// parameterizes (`CodeArtifact.sequenceDiagram`).
public struct SequenceDiagramConfiguration: Codable, Hashable, Sendable {
    public var entryTypeName: String
    public var entryMethodName: String
    /// Maximum call-graph traversal depth.
    public var maxDepth: Int
    /// Maps protocol/interface names to the concrete type whose body should be followed.
    public var typeMapping: [String: String]

    public init(
        entryTypeName: String,
        entryMethodName: String,
        maxDepth: Int = 5,
        typeMapping: [String: String] = [:]
    ) {
        self.entryTypeName = entryTypeName
        self.entryMethodName = entryMethodName
        self.maxDepth = maxDepth
        self.typeMapping = typeMapping
    }
}

extension CodeArtifact {
    /// Generates a `SequenceDiagram` from a stored configuration; see
    /// `sequenceDiagram(entryPoint:title:maxDepth:typeMapping:)`.
    public func sequenceDiagram(
        configuration: SequenceDiagramConfiguration,
        title: String? = nil
    ) -> SequenceDiagram {
        sequenceDiagram(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            title: title,
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        )
    }
}
