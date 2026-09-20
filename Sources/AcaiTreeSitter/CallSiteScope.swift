import AcaiCore

/// What a body walker knows about the names in scope while classifying a call's receiver.
///
/// Resolution stays deliberately conservative — a call site is only captured when its receiver is
/// provably a known type: a typed stored property, an explicit `this`/`self`, or a
/// `TypeName.method()` where `TypeName` is declared. Anything else is dropped, keeping the
/// resulting sequence diagrams near-zero-false-edge.
public struct CallSiteScope: Sendable {

    /// Stored properties with a determinable type — call-site resolution needs the type.
    public var knownProperties: [String: String]

    /// Simple names of types declared in the current file (for `TypeName.method()`).
    public var knownTypeNames: Set<String>

    /// Names of **all** the enclosing type's stored properties, including untyped ones (e.g.
    /// Python's `self.x = …`). Field-read capture filters by name only, so it needs the full set —
    /// not just the typed subset in ``knownProperties``.
    public var knownPropertyNames: Set<String>

    /// Unambiguous overloads only, so a local initialized from a same-type method call
    /// (`let x = compute()`) can have its type inferred the same way a direct construction already
    /// does.
    public var knownMethodReturnTypes: [String: String]

    public init(
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

    /// Everything a type's own members say about its names, in one step.
    public init(members: MemberIndex, knownTypeNames: Set<String>) {
        self.init(
            knownProperties: members.propertyTypes,
            knownTypeNames: knownTypeNames,
            knownPropertyNames: members.propertyNames,
            knownMethodReturnTypes: members.methodReturnTypes
        )
    }

    /// A typed stored property resolves to its declared type; a known type name is a static call; a
    /// capitalised name matching neither is deferred (`.unresolvedTypeName`), possibly declared
    /// elsewhere in the project, resolved post-merge. Returns `nil` for locals/parameters/external
    /// receivers.
    public func resolvedCallSite(
        receiverName: String,
        methodName: String,
        location: SourceLocation?
    ) -> CallSite? {
        if let receiverType = knownProperties[receiverName] {
            return CallSite(receiver: .type(receiverType), methodName: methodName, location: location)
        }
        if knownTypeNames.contains(receiverName) {
            return CallSite(receiver: .type(receiverName), methodName: methodName, location: location)
        }
        if receiverName.first?.isUppercase == true {
            return CallSite(receiver: .unresolvedTypeName(receiverName), methodName: methodName, location: location)
        }
        return nil
    }

    /// Leaves `knownPropertyNames` untouched, since a local isn't a field.
    public func merging(locals: [String: String]) -> CallSiteScope {
        guard !locals.isEmpty else { return self }
        var copy = self
        copy.knownProperties = knownProperties.merging(locals) { _, local in local }
        return copy
    }

    /// Overlays each parameter's provable declared type onto `knownProperties`, so `param.method()`
    /// resolves like a typed stored property.
    public func merging(parameters: [Parameter]) -> CallSiteScope {
        let map = Dictionary(
            parameters.compactMap { parameter in parameter.type.map { (parameter.internalName, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        return merging(locals: map)
    }

    /// Resolves a bare `foo()` with no explicit receiver. Skipped when `name` is a known type (it's
    /// a construction, not a call). `implicitSelf` tags it `.selfDispatch` for languages with an
    /// implicit receiver — resolved against the enclosing type first, then a free function;
    /// otherwise `.free` (e.g. JS, which has no implicit `this`).
    public func bareCall(named name: String, implicitSelf: Bool, location: SourceLocation?) -> CallSite? {
        guard !knownTypeNames.contains(name) else { return nil }
        return CallSite(receiver: implicitSelf ? .selfDispatch : .free, methodName: name, location: location)
    }
}
