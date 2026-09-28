import AcaiCore
import AcaiDiagram

/// The two-step "new sequence diagram" flow: pick an entry point, then map every abstraction the
/// first-pass trace actually reached to a concrete conformer, so the diagram can follow real
/// implementations instead of stopping at the abstraction.
public struct SequenceConfigModel: Sendable {
    public enum Step: Hashable, Sendable {
        case entryPoint
        case resolveInterfaces
    }

    /// Advancing past the entry-point step either has abstractions to resolve or nothing left to
    /// ask, in which case the configuration is already complete.
    public enum Advance: Hashable, Sendable {
        case resolveInterfaces
        case finished(SequenceDiagramConfiguration)
    }

    public struct InterfaceMapping: Identifiable, Hashable, Sendable {
        public var id: String { protocolName }
        public let protocolName: String
        public let candidates: [String]
        /// The chosen concrete type; `nil` leaves the participant abstract.
        public var selection: String?
    }

    private let artifact: CodeArtifact
    private let initial: SequenceDiagramConfiguration?

    public private(set) var step: Step = .entryPoint
    /// Empty is the top-level (no class) scope — it round-trips directly, so re-editing a
    /// free-function entry restores the right picker state with no translation.
    public private(set) var entryTypeName: String
    public var entryMethodName: String
    public var maxDepth: Int
    public private(set) var mappings: [InterfaceMapping] = []

    public init(artifact: CodeArtifact, initial: SequenceDiagramConfiguration? = nil) {
        self.artifact = artifact
        self.initial = initial
        entryTypeName = initial?.entryTypeName ?? ""
        entryMethodName = initial?.entryMethodName ?? ""
        maxDepth = initial?.maxDepth ?? 5
    }

    // MARK: - Steps

    public var canAdvance: Bool { !entryMethodName.isEmpty }

    /// Changing the scope invalidates a method that only existed on the previous one, so the
    /// selection moves to the new scope's first method rather than silently staying untraceable.
    public mutating func selectEntryType(_ name: String) {
        entryTypeName = name
        if !methodNames.contains(entryMethodName) {
            entryMethodName = methodNames.first ?? ""
        }
    }

    public mutating func advance() -> Advance {
        mappings = resolvableMappings()
        guard !mappings.isEmpty else { return .finished(configuration) }
        step = .resolveInterfaces
        return .resolveInterfaces
    }

    public mutating func back() {
        step = .entryPoint
    }

    /// `nil` leaves that abstraction abstract. An unknown name is ignored rather than added, so a
    /// selection made against a mapping list that has since been rebuilt can't invent a row.
    public mutating func select(_ concreteType: String?, forAbstractionNamed protocolName: String) {
        guard let index = mappings.firstIndex(where: { $0.protocolName == protocolName }) else { return }
        mappings[index].selection = concreteType
    }

    public var configuration: SequenceDiagramConfiguration {
        var typeMapping: [String: String] = [:]
        for mapping in mappings {
            if let concrete = mapping.selection { typeMapping[mapping.protocolName] = concrete }
        }
        return SequenceDiagramConfiguration(
            entryTypeName: entryTypeName,
            entryMethodName: entryMethodName,
            maxDepth: maxDepth,
            typeMapping: typeMapping
        )
    }

    /// One row per abstraction the trace reaches that has at least one conformer to offer. The
    /// mapping key stays the raw participant name (existential spellings included) because the
    /// generator substitutes receiver strings verbatim.
    private func resolvableMappings() -> [InterfaceMapping] {
        let preview = SequenceDiagramBuilder(
            entryPoint: (entryTypeName, entryMethodName), maxDepth: maxDepth
        ).build(from: artifact)
        var rows: [InterfaceMapping] = []
        var seen: Set<String> = []
        for participant in preview.participants where seen.insert(participant.name).inserted {
            let candidates = artifact.conformerNames(ofAbstractionNamed: participant.name)
            guard !candidates.isEmpty else { continue }
            rows.append(InterfaceMapping(
                protocolName: participant.name,
                candidates: candidates,
                selection: initial?.typeMapping[participant.name]
            ))
        }
        return rows
    }

    // MARK: - Lookups

    /// The codebase's top-level (free) functions — the entry points available when no class is
    /// selected (an empty entry-type name, which `sequenceDiagram(entryPoint:)` resolves against
    /// `freestandingFunctions`).
    public var freeFunctionNames: [String] {
        artifact.freestandingFunctions.map(\.name).uniqued().sorted()
    }

    public var callableTypeNames: [String] {
        artifact.types
            .filter { $0.members.contains { $0.kind == .method } }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    public var methodNames: [String] {
        guard !entryTypeName.isEmpty else { return freeFunctionNames }
        guard let type = artifact.types.first(where: { $0.name == entryTypeName }) else { return [] }
        return type.members
            .filter { $0.kind == .method }
            .map(\.name)
            .uniqued()
            .sorted()
    }
}
