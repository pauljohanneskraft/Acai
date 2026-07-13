import UMLCore

/// The statically-known context used to classify a call/assignment/field-read's receiver, scoped to
/// one member's enclosing type (or, for a freestanding function, the module).
///
/// Deliberately conservative — a receiver only resolves when it is *provably* a known type: a typed
/// stored property, an explicit `self`/`this`, a `TypeName.method()`, or (generalizing the same
/// mechanism) any other identifier with a statically-known declared type — which is what makes a C
/// free function's typed pointer parameter (`Download *d`) resolve `d->state` the same way a typed
/// property would, with no special-casing: it's simply another entry in `knownProperties`.
struct KnownMemberIndex: Sendable {
    /// `identifierName: typeName` for every statically-typed receiver in scope: the enclosing type's
    /// stored properties, its method parameters, and (via `merging(locals:)`) local bindings.
    var knownProperties: [String: String]
    /// Simple names of every type declared in the current file (for `TypeName.method()` calls).
    var knownTypeNames: Set<String>
    /// Every stored-property name, including untyped ones (e.g. Python's `self.x = …`) —
    /// field-read capture filters by name only, so it needs the full set, not just the typed subset
    /// in `knownProperties`. Defaults to `knownProperties`'s keys when unspecified.
    var knownPropertyNames: Set<String>
    /// `methodName: returnTypeName` for the enclosing type's own methods (unambiguous overloads
    /// only), so a same-type method call can seed a local's type the same way a direct construction
    /// already does.
    var knownMethodReturnTypes: [String: String]

    init(
        knownProperties: [String: String] = [:],
        knownTypeNames: Set<String> = [],
        knownPropertyNames: Set<String>? = nil,
        knownMethodReturnTypes: [String: String] = [:]
    ) {
        self.knownProperties = knownProperties
        self.knownTypeNames = knownTypeNames
        self.knownPropertyNames = knownPropertyNames ?? Set(knownProperties.keys)
        self.knownMethodReturnTypes = knownMethodReturnTypes
    }

    /// Derives an index from a type's (or module's) already-assembled sibling members: typed
    /// properties seed `knownProperties`, every property name (typed or not) seeds
    /// `knownPropertyNames`, and methods with an unambiguous return type seed
    /// `knownMethodReturnTypes`.
    init(members: [Member], knownTypeNames: Set<String>) {
        var properties: [String: String] = [:]
        var propertyNames: Set<String> = []
        var returnTypesByName: [String: Set<String>] = [:]
        for member in members {
            switch member.kind {
            case .property, .subscript:
                propertyNames.insert(member.name)
                if let type = member.type { properties[member.name] = type.name }
            case .method:
                if let type = member.type { returnTypesByName[member.name, default: []].insert(type.name) }
            case .initializer, .deinitializer:
                break
            }
        }
        self.init(
            knownProperties: properties, knownTypeNames: knownTypeNames, knownPropertyNames: propertyNames,
            knownMethodReturnTypes: returnTypesByName.compactMapValues { $0.count == 1 ? $0.first : nil })
    }

    /// A copy with `locals` overlaid onto `knownProperties` (a local shadows a same-named stored
    /// property). Leaves `knownPropertyNames` untouched — a local is not a field.
    func merging(locals: [String: String]) -> KnownMemberIndex {
        guard !locals.isEmpty else { return self }
        var copy = self
        copy.knownProperties = knownProperties.merging(locals) { _, local in local }
        return copy
    }

    /// A copy with each parameter's declared type overlaid onto `knownProperties`, so `param.method()`
    /// resolves the same way a typed stored property does — and, generalized, so does `param->field`
    /// in a free function for C's pointer-based state-machine idiom (no separate mechanism needed:
    /// a parameter is just another named, typed receiver).
    func merging(parameters: [Parameter]) -> KnownMemberIndex {
        let typed = Dictionary(
            parameters.compactMap { parameter in parameter.type.map { (parameter.internalName, $0.name) } },
            uniquingKeysWith: { first, _ in first })
        return merging(locals: typed)
    }
}
