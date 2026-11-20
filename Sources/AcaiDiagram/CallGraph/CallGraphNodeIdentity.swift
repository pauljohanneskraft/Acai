import AcaiCore

/// The one speller of call-graph node ids: type (qualified when its simple name is shared), member
/// name and parameter list, plus the declaring file for a free function.
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

    /// Scoped by the declaring file; bare when the parser recorded no location.
    func nodeID(forFreeFunction function: Member) -> String {
        let signature = function.callGraphParameterList ?? ""
        guard let path = function.location?.filePath, !path.isEmpty else {
            return "\(function.name)\(signature)"
        }
        return "\(path):\(function.name)\(signature)"
    }

    func container(forFreeFunction function: Member) -> String? {
        guard let path = function.location?.filePath, !path.isEmpty else { return nil }
        return path.split(separator: "/").last.map(String.init)
    }
}
