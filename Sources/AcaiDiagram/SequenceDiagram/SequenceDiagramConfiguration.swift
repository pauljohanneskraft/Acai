import AcaiCore
import AcaiQuality

/// Describes how a sequence diagram is traced from a codebase: the starting method, how deep
/// to follow calls, and how abstract receiver types resolve to concrete ones. The counterpart
/// of `ClassDiagramConfiguration` for sequence diagrams; lives next to the generator it
/// parameterizes (`CodeArtifact.sequenceDiagram`).
public struct SequenceDiagramConfiguration: Codable, Hashable, Sendable {
    public var entryTypeName: String
    public var entryMethodName: String
    public var maxDepth: Int
    /// Maps protocol/interface names to the concrete type whose body should be followed.
    public var typeMapping: [String: String]
    /// When set, only participants this selector matches are shown (their messages drop with
    /// them); the trace's entry-point participant is always exempt, since hiding the root of the
    /// trace would defeat the diagram's purpose. `nil` (the default) shows every participant.
    public var filter: AcaiQuality.Selector?

    public init(
        entryTypeName: String,
        entryMethodName: String,
        maxDepth: Int = 5,
        typeMapping: [String: String] = [:],
        filter: AcaiQuality.Selector? = nil
    ) {
        self.entryTypeName = entryTypeName
        self.entryMethodName = entryMethodName
        self.maxDepth = maxDepth
        self.typeMapping = typeMapping
        self.filter = filter
    }
}

extension SequenceDiagramBuilder {
    public init(configuration: SequenceDiagramConfiguration, title: String? = nil) {
        self.init(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            title: title,
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        )
    }
}
