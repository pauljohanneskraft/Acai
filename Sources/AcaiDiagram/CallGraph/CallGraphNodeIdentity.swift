import AcaiCore

/// The identity a call-graph node or dead-code candidate is keyed on — the one place node ids are
/// spelled, so the builder, the dead-code scan and the location index cannot drift apart.
///
/// Three things make up an id:
/// - the owning type's simple ``TypeDeclaration/name`` when that name resolves uniquely to it via
///   ``TypeIdentityResolver``, its qualified ``TypeDeclaration/id`` otherwise — so two declared
///   types sharing a simple name (e.g. `Config` in two modules) get distinct ids;
/// - the member's name plus its ``Member/callGraphParameterList``, so overloads are distinct nodes
///   rather than one merged node where each overload looks like a caller of itself;
/// - for a free function, the file that declares it, so same-named file-local functions (a C
///   `static` helper, a Python module-level function) in different files stay distinct.
///
/// A value you instantiate once over the artifact's flattened types and query per member.
struct CallGraphNodeIdentity: Sendable {
    private let resolver: TypeIdentityResolver

    init(types: [TypeDeclaration]) {
        resolver = TypeIdentityResolver(types: types)
    }

    /// The name to key `type`'s nodes/candidates by.
    func nodeName(for type: TypeDeclaration) -> String {
        resolver.resolvedID(for: type.name)?.value == type.id ? type.name : type.id
    }

    func nodeID(for member: Member, in type: TypeDeclaration) -> String {
        "\(nodeName(for: type)).\(member.name)\(member.callGraphParameterList ?? "")"
    }

    /// A free function's id, scoped by its declaring file. A function whose parser recorded no
    /// location keeps the bare name — there is nothing to scope it by.
    func nodeID(forFreeFunction function: Member) -> String {
        let signature = function.callGraphParameterList ?? ""
        guard let path = function.location?.filePath, !path.isEmpty else {
            return "\(function.name)\(signature)"
        }
        return "\(path):\(function.name)\(signature)"
    }

    /// What a free function's node shows as its qualifier: the file's name, the readable part of the
    /// path its id is scoped by. `nil` when the function carries no location.
    func container(forFreeFunction function: Member) -> String? {
        guard let path = function.location?.filePath, !path.isEmpty else { return nil }
        return path.split(separator: "/").last.map(String.init)
    }
}
