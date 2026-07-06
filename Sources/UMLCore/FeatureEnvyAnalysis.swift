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
        let ownProperties = Set(type.members.filter(\.isStoredProperty).map(\.name))
        return type.members.filter { $0.kind == .method && isEnvious($0, ownProperties: ownProperties) }.count
    }

    /// A method is envious when its heaviest interaction with a single foreign declared type outweighs
    /// its interaction with its own type (self-dispatched calls plus reads of its own stored
    /// properties). Methods that touch nothing foreign never qualify.
    private func isEnvious(_ method: Member, ownProperties: Set<String>) -> Bool {
        var foreign: [String: Int] = [:]
        var own = 0
        for call in method.callSites {
            switch classify(call.receiver) {
            case .own:
                own += 1
            case .foreign(let id):
                foreign[id, default: 0] += 1
            case .unknown:
                continue
            }
        }
        // Reads of the method's own stored properties count toward "own" (issue #111).
        for read in method.fieldReads where read.receiver == nil && ownProperties.contains(read.name) {
            own += 1
        }
        for name in method.referencedTypeNames {
            if case .foreign(let id) = classifyTypeName(name) { foreign[id, default: 0] += 1 }
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

    /// Classifies a call's dispatch: `self` and calls on the type's own name are `.own`; a call on
    /// another declared type is `.foreign`; free-function and unresolved calls are `.unknown` (issue
    /// #111 — a nil receiver is no longer assumed to be `self`).
    private func classify(_ receiver: CallReceiver) -> Target {
        switch receiver {
        case .selfDispatch:
            return .own
        case .type(let name):
            return classifyTypeName(name)
        case .free, .unknown:
            return .unknown
        }
    }

    private func classifyTypeName(_ name: String) -> Target {
        if name == type.name { return .own }
        guard let id = identity.resolvedID(for: name)?.value, id != type.id else { return .unknown }
        return .foreign(id)
    }
}
