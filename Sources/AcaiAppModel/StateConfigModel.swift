import AcaiCore
import AcaiDiagram

/// The "new state diagram" form: which scope's stored properties can define a state space, which of
/// them are plausible state holders, and the configuration the choice produces.
public struct StateConfigModel: Sendable {
    public enum Scope: Hashable, Sendable {
        case type(String)
        case globals
    }

    public private(set) var scope: Scope?
    public var variableName: String
    public var maxStates: Int

    /// Labels each id in ``typeIDsWithStoredProperties``.
    public let typeDisplayNames: TypeDisplayNames
    /// Ids, not names, so nested and same-named types each stay reachable; ordered by their label.
    public let typeIDsWithStoredProperties: [String]
    public let hasGlobalVariables: Bool

    private let variableNamesByScope: [Scope: [String]]

    public init(
        artifact: CodeArtifact,
        initial: StateDiagramConfiguration? = nil,
        walkObserver: AnalysisWalkObserver? = nil
    ) {
        let lookups = StateScopeLookups(artifact: artifact, walkObserver: walkObserver)
        typeDisplayNames = lookups.displayNames
        typeIDsWithStoredProperties = lookups.typeIDs
        variableNamesByScope = lookups.variableNamesByScope
        hasGlobalVariables = !artifact.globalVariables.isEmpty
        scope = initial.map { $0.typeName.map(Scope.type) ?? .globals }
        variableName = initial?.variableName ?? ""
        maxStates = initial?.maxStates ?? 20
    }

    public var canCreate: Bool { scope != nil && !variableName.isEmpty }

    /// Changing the scope invalidates a variable that only existed in the previous one, so the
    /// selection moves to the new scope's first variable rather than staying unresolvable.
    public mutating func selectScope(_ newScope: Scope?) {
        scope = newScope
        if !variableNames.contains(variableName) {
            variableName = variableNames.first ?? ""
        }
    }

    public var configuration: StateDiagramConfiguration {
        let typeName: String? = if case .type(let name) = scope { name } else { nil }
        return StateDiagramConfiguration(
            typeName: typeName, variableName: variableName, maxStates: maxStates
        )
    }

    /// Plausible state holders first — an enum, boolean, integer or string property is what a state
    /// space is usually built from, and in a large type those would otherwise be buried.
    public var variableNames: [String] {
        guard let scope else { return [] }
        return variableNamesByScope[scope] ?? []
    }
}

/// Every scope's option list, derived in one pass over the analysis.
private struct StateScopeLookups {
    let displayNames: TypeDisplayNames
    let typeIDs: [String]
    let variableNamesByScope: [StateConfigModel.Scope: [String]]

    init(artifact: CodeArtifact, walkObserver: AnalysisWalkObserver?) {
        walkObserver?.didWalk()
        var storedProperties: [(id: String, members: [Member])] = []
        var enumTypeNames: Set<String> = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.kind == .enum { enumTypeNames.insert(type.name) }
                let stored = type.members.filter { $0.kind == .property && !$0.isComputed }
                if !stored.isEmpty { storedProperties.append((type.id, stored)) }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)

        let names = artifact.typeDisplayNames
        displayNames = names
        typeIDs = storedProperties.map(\.id).uniqued()
            .sorted { (names.name(forID: $0), $0) < (names.name(forID: $1), $1) }

        let ordering = StateHolderOrdering(enumTypeNames: enumTypeNames)
        var byScope: [StateConfigModel.Scope: [String]] = [:]
        for entry in storedProperties where byScope[.type(entry.id)] == nil {
            byScope[.type(entry.id)] = ordering.names(of: entry.members)
        }
        byScope[.globals] = ordering.names(of: artifact.globalVariables)
        variableNamesByScope = byScope
    }
}

/// Orders a scope's stored properties so the ones a state space is usually built from come first.
private struct StateHolderOrdering {
    let enumTypeNames: Set<String>

    private let primitiveNames: Set<String> = ["bool", "boolean", "int", "integer", "string"]

    func names(of members: [Member]) -> [String] {
        let plausible = members.filter(isPlausible).map(\.name)
        let rest = members.filter { !isPlausible($0) }.map(\.name)
        return (plausible.uniqued().sorted() + rest.uniqued().sorted()).uniqued()
    }

    private func isPlausible(_ member: Member) -> Bool {
        guard let typeName = member.type?.name else { return false }
        if enumTypeNames.contains(typeName) { return true }
        return primitiveNames.contains(typeName.lowercased())
    }
}
