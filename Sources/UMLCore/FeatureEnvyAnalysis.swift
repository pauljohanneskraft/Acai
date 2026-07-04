/// Feature-envy detection for a type: how many of its methods talk to *another* declared type more
/// than to the type they belong to (Fowler's "a method more interested in another class than its
/// own"). A high count marks logic living in the wrong place — behaviour that wants to move to the
/// type it envies. A value you instantiate (it needs the artifact's ``TypeIdentityResolver`` to bind
/// receiver names to declared types) and ask for ``enviousMethodCount``.
struct FeatureEnvy {
    let type: TypeDeclaration
    let identity: TypeIdentityResolver

    init(type: TypeDeclaration, identity: TypeIdentityResolver) {
        self.type = type
        self.identity = identity
    }

    /// Count of methods that interact with some single other declared type more than with their owner.
    var enviousMethodCount: Int {
        type.members.filter { $0.kind == .method && isEnvious($0) }.count
    }

    /// A method is envious when its heaviest interaction with a single foreign declared type outweighs
    /// its interaction with its own type (self calls). Methods that touch nothing foreign never qualify.
    /// Own-field *reads* aren't captured by parsers, so "own" is self-calls only — see issue #111.
    private func isEnvious(_ method: Member) -> Bool {
        var foreign: [String: Int] = [:]
        var own = 0
        for call in method.callSites {
            switch classify(receiver: call.receiverType) {
            case .own:
                own += 1
            case .foreign(let id):
                foreign[id, default: 0] += 1
            case .unknown:
                continue
            }
        }
        for name in method.referencedTypeNames {
            if case .foreign(let id) = classify(receiver: name) { foreign[id, default: 0] += 1 }
        }
        return (foreign.values.max() ?? 0) > own
    }

    /// Where an interaction is directed: the type itself, another declared type (by id), or an
    /// unresolved/external reference that doesn't count either way.
    private enum Target {
        case own
        case foreign(String)
        case unknown
    }

    private func classify(receiver: String?) -> Target {
        guard let receiver else { return .own }        // no receiver = a call on `self`
        if receiver == type.name { return .own }
        guard let id = identity.resolvedID(for: receiver)?.value, id != type.id else { return .unknown }
        return .foreign(id)
    }
}
