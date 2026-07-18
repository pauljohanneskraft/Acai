/// Infers a type's structural relationship edges from its declared members — the behaviour that used
/// to live as `static func`s on `CodeArtifact` (reaching into `TypeDeclaration`/`Member`/`TypeReference`
/// is envy the model shouldn't carry). A value you instantiate with the language's type-name
/// classification and an id resolver, then ask for a type's ``edges(for:)``:
///
/// - properties/subscripts → composition (scalar) or aggregation (collection),
/// - method/initializer parameter & return types → dependency (deduped per type),
/// - a `typealias` target → dependency on its underlying type.
struct StructuralEdgeInference {
    /// Classifies primitive/collection type names (injected, language-supplied).
    let configuration: LanguageConfiguration
    /// Maps a referenced type name to its canonical id.
    let resolveId: (String) -> String

    init(configuration: LanguageConfiguration, resolveId: @escaping (String) -> String) {
        self.configuration = configuration
        self.resolveId = resolveId
    }

    /// Every inferred structural edge originating at `type`.
    func edges(for type: TypeDeclaration) -> [Relationship] {
        propertyEdges(for: type) + methodEdges(for: type) + typeAliasEdges(for: type)
    }

    /// Properties/subscripts → composition (scalar) or aggregation (collection).
    private func propertyEdges(for type: TypeDeclaration) -> [Relationship] {
        var edges: [Relationship] = []
        for member in type.members where member.kind == .property || member.kind == .subscript {
            guard let typeRef = member.type else { continue }
            for refName in referencedTypeNames(from: typeRef) {
                let targetId = resolveId(refName)
                guard targetId != type.id else { continue }
                let isCollection = typeRef.isArray || configuration.isCollectionType(typeRef.name)
                let multiplicity: String = isCollection ? "*" : (typeRef.isOptional ? "0..1" : "1")
                edges.append(Relationship(
                    kind: isCollection ? .aggregation : .composition,
                    source: type.id, target: targetId,
                    targetLabel: multiplicity, label: member.name,
                    origin: member.location?.filePath))
            }
        }
        return edges
    }

    /// Method/initializer parameter & return types → dependency (deduped per type).
    private func methodEdges(for type: TypeDeclaration) -> [Relationship] {
        var edges: [Relationship] = []
        var seen = Set<String>()
        for member in type.members where member.kind == .method || member.kind == .initializer {
            let refs = ([member.type].compactMap { $0 }) + member.parameters.compactMap(\.type)
            for ref in refs {
                for refName in referencedTypeNames(from: ref) {
                    let targetId = resolveId(refName)
                    guard targetId != type.id, seen.insert(targetId).inserted else { continue }
                    edges.append(Relationship(
                        kind: .dependency, source: type.id, target: targetId,
                        origin: member.location?.filePath))
                }
            }
        }
        return edges
    }

    /// `typealias` → dependency on its underlying type.
    private func typeAliasEdges(for type: TypeDeclaration) -> [Relationship] {
        guard type.kind == .typeAlias else { return [] }
        var edges: [Relationship] = []
        for ref in type.inheritedTypes {
            for refName in referencedTypeNames(from: ref) {
                let targetId = resolveId(refName)
                guard targetId != type.id else { continue }
                edges.append(Relationship(
                    kind: .dependency, source: type.id, target: targetId,
                    origin: type.location?.filePath))
            }
        }
        return edges
    }

    /// Type names referenced by a `TypeReference` (incl. generic args), excluding names the language's
    /// `configuration` classifies as primitives or collection containers.
    func referencedTypeNames(from ref: TypeReference) -> [String] {
        var names: [String] = []
        if !configuration.isPrimitive(ref.name) && !configuration.isCollectionType(ref.name) {
            names.append(ref.name)
        }
        for arg in ref.genericArguments {
            names.append(contentsOf: referencedTypeNames(from: arg))
        }
        return names
    }
}
