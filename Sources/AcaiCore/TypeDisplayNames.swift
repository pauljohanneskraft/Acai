/// How a user-facing label names a type: by ``TypeDeclaration/unqualifiedID``, the id as its source
/// spells it, unless another type in the codebase spells it the same — then by its unique ``TypeDeclaration/id``.
public struct TypeDisplayNames: Sendable {
    private let nameByID: [String: String]

    /// `types` is every type of the codebase, nested ones included — a namesake outside it goes unnoticed.
    public init(types: [TypeDeclaration]) {
        let declared = types.filter { $0.kind != .extension }
        var count: [String: Int] = [:]
        for type in declared {
            count[type.unqualifiedID, default: 0] += 1
        }
        var nameByID: [String: String] = [:]
        for type in declared {
            nameByID[type.id] = count[type.unqualifiedID] == 1 ? type.unqualifiedID : type.id
        }
        self.nameByID = nameByID
    }

    /// An id no declared type carries (a module, an external type) is returned unchanged.
    public func name(forID id: String) -> String {
        nameByID[id] ?? id
    }

    public func name(for type: TypeDeclaration) -> String {
        name(forID: type.id)
    }
}

extension CodeArtifact {
    public var typeDisplayNames: TypeDisplayNames {
        TypeDisplayNames(types: flattened())
    }
}
