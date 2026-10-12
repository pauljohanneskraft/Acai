import AcaiCore
import AcaiDiagram

/// The "new state diagram" form: which scope's stored properties can define a state space, which of
/// them are plausible state holders, and the configuration the choice produces.
public struct StateConfigModel: Sendable {
    public enum Scope: Hashable, Sendable {
        case type(String)
        case globals
    }

    private let artifact: CodeArtifact

    public private(set) var scope: Scope?
    public var variableName: String
    public var maxStates: Int

    public init(artifact: CodeArtifact, initial: StateDiagramConfiguration? = nil) {
        self.artifact = artifact
        scope = initial.map { $0.typeName.map(Scope.type) ?? .globals }
        variableName = initial?.variableName ?? ""
        maxStates = initial?.maxStates ?? 20
    }

    public var canCreate: Bool { scope != nil && !variableName.isEmpty }

    public var hasGlobalVariables: Bool { !artifact.globalVariables.isEmpty }

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

    // MARK: - Lookups

    /// Labels each id in ``typeIDsWithStoredProperties``.
    public var typeDisplayNames: TypeDisplayNames {
        artifact.typeDisplayNames
    }

    /// Ids, not names, so nested and same-named types each stay reachable; ordered by their label.
    public var typeIDsWithStoredProperties: [String] {
        let names = typeDisplayNames
        return typesWithStoredProperties.map(\.id).uniqued()
            .sorted { (names.name(forID: $0), $0) < (names.name(forID: $1), $1) }
    }

    /// Plausible state holders first — an enum, boolean, integer or string property is what a state
    /// space is usually built from, and in a large type those would otherwise be buried.
    public var variableNames: [String] {
        let members: [Member]
        switch scope {
        case .type(let id):
            members = typesWithStoredProperties.first { $0.id == id }?
                .members.filter { $0.kind == .property && !$0.isComputed } ?? []
        case .globals:
            members = artifact.globalVariables
        case nil:
            return []
        }
        let plausible = members.filter { isPlausibleStateHolder($0) }.map(\.name)
        let rest = members.filter { !isPlausibleStateHolder($0) }.map(\.name)
        return (plausible.uniqued().sorted() + rest.uniqued().sorted()).uniqued()
    }

    /// Mirrors `StateAnalysis.findType`, which recurses into `nestedTypes` and matches on
    /// `qualifiedName`, which equals `id`.
    private var typesWithStoredProperties: [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.members.contains(where: { $0.kind == .property && !$0.isComputed }) {
                    result.append(type)
                }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return result
    }

    private func isPlausibleStateHolder(_ member: Member) -> Bool {
        guard let typeName = member.type?.name else { return false }
        if enumTypeNames.contains(typeName) { return true }
        return ["bool", "boolean", "int", "integer", "string"].contains(typeName.lowercased())
    }

    private var enumTypeNames: Set<String> {
        var names: Set<String> = []
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                if type.kind == .enum { names.insert(type.name) }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return names
    }
}
