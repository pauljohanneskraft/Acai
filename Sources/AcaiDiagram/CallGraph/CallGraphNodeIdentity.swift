import AcaiCore

/// The identity a call-graph node or dead-code candidate uses for a type: its simple
/// ``TypeDeclaration/name`` when that name resolves uniquely to it via ``TypeIdentityResolver``, its
/// qualified ``TypeDeclaration/id`` otherwise — so two declared types that share a simple name (e.g.
/// `Config` in two different modules) get distinct node ids instead of silently merging into one.
///
/// A value you instantiate once over the artifact's flattened types and query per type.
struct CallGraphNodeIdentity: Sendable {
    private let resolver: TypeIdentityResolver

    init(types: [TypeDeclaration]) {
        resolver = TypeIdentityResolver(types: types)
    }

    /// The name to key `type`'s nodes/candidates by.
    func nodeName(for type: TypeDeclaration) -> String {
        resolver.resolvedID(for: type.name)?.value == type.id ? type.name : type.id
    }
}
