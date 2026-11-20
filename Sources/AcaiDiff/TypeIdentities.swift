import AcaiCore

/// Matches types across revisions by module plus qualified name, which survives the path re-scoping
/// of colliding and private ids; the file path only breaks a tie within one module.
struct TypeIdentities: Sendable {
    /// One revision's type ids mapped to their cross-revision identity.
    struct Side: Sendable {
        private let identitiesByID: [String: String]

        init(types: [TypeDeclaration], keys: [String], ambiguous: Set<String>) {
            var identities: [String: String] = [:]
            for (type, key) in zip(types, keys) {
                identities[type.id] = ambiguous.contains(key)
                    ? "\(key)\u{1}\(type.location?.filePath ?? "")"
                    : key
            }
            identitiesByID = identities
        }

        /// An undeclared id, such as an external relationship endpoint, is its own identity.
        func identity(of id: String) -> String { identitiesByID[id] ?? id }

        func key(of relationship: Relationship) -> String {
            let source = identity(of: relationship.source)
            let target = identity(of: relationship.target)
            return "\(source)\u{1}\(target)\u{1}\(relationship.kind.rawValue)"
        }
    }

    let old: Side
    let new: Side

    init(old: [TypeDeclaration], new: [TypeDeclaration], moduleResolver: ModuleResolver) {
        let oldKeys = old.map { $0.stableDiffKey(resolvedBy: moduleResolver) }
        let newKeys = new.map { $0.stableDiffKey(resolvedBy: moduleResolver) }

        var ambiguous: Set<String> = []
        for keys in [oldKeys, newKeys] {
            var seen: Set<String> = []
            for key in keys where !seen.insert(key).inserted { ambiguous.insert(key) }
        }

        self.old = Side(types: old, keys: oldKeys, ambiguous: ambiguous)
        self.new = Side(types: new, keys: newKeys, ambiguous: ambiguous)
    }
}

extension TypeDeclaration {
    /// Module plus the id with its file or module scope stripped.
    fileprivate func stableDiffKey(resolvedBy moduleResolver: ModuleResolver) -> String {
        let filePath = location?.filePath ?? ""
        let module = module ?? moduleResolver.productName(forFilePath: filePath)
        let scope = TypeIDScope(filePath: filePath, module: module)
        return "\(module).\(scope.unqualified(id))"
    }
}

extension Relationship {
    /// What `diffKey` leaves out, so a re-scoped endpoint id is never mistaken for a label change.
    var labelSignature: String {
        "\(sourceLabel ?? "")\u{1}\(targetLabel ?? "")\u{1}\(label ?? "")"
    }
}
