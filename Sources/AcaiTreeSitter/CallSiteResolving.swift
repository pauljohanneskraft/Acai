import Foundation
import AcaiCore

// MARK: - CallSiteScope

/// Resolution stays deliberately conservative — a call site is only captured when its receiver is
/// provably a known type: a typed stored property, an explicit `this`/`self`, or a
/// `TypeName.method()` where `TypeName` is declared. Anything else is dropped, keeping the resulting
/// sequence diagrams near-zero-false-edge.
public struct CallSiteScope: Sendable {
    /// Stored properties with a determinable type — call-site resolution needs the type.
    public var knownProperties: [String: String]
    /// Simple names of types declared in the current file (for `TypeName.method()`).
    public var knownTypeNames: Set<String>
    /// Names of **all** the enclosing type's stored properties, including untyped ones (e.g. Python's
    /// `self.x = …`). Field-read capture filters by name only, so it needs the full set — not just
    /// the typed subset in ``knownProperties``.
    public var knownPropertyNames: Set<String>
    /// Unambiguous overloads only, so a local initialized from a same-type method call
    /// (`let x = compute()`) can have its type inferred the same way a direct construction already does.
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

    /// Resolves a bare `foo()` with no explicit receiver. Skipped when `name` is a known type (it's a
    /// construction, not a call). `implicitSelf` tags it `.selfDispatch` for languages with an implicit
    /// receiver — resolved against the enclosing type first, then a free function; otherwise `.free`
    /// (e.g. JS, which has no implicit `this`).
    public func bareCall(named name: String, implicitSelf: Bool, location: SourceLocation?) -> CallSite? {
        guard !knownTypeNames.contains(name) else { return nil }
        return CallSite(receiver: implicitSelf ? .selfDispatch : .free, methodName: name, location: location)
    }
}

// MARK: - CallSiteResolving

/// Opt-in protocol for extractors that support call-site resolution (not every language needs it,
/// e.g. Dart doesn't).
public protocol CallSiteResolving: TreeSitterExtracting {

    func resolveCallSite(
        _ node: Node,
        scope: CallSiteScope
    ) -> CallSite?

    /// Local-variable name → provably-declared type, collected from a body so calls on locals resolve
    /// (`var x = Foo(); x.method()`). Default: no locals. A language overrides this to recognise its
    /// typed/constructed local declarations, emitting only provable types.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String]
}

// MARK: - CallSiteResolving Default Implementations

extension CallSiteResolving {

    public func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] { [:] }

    /// A language's ``localBindings(in:)`` uses this so it only writes a per-node recogniser, not the
    /// traversal. A later binding for the same name wins.
    public func collectLocalBindings(
        in body: Node, binding: (Node) -> (name: String, type: String)?
    ) -> [String: String] {
        var map: [String: String] = [:]
        func walk(_ node: Node) {
            if let found = binding(node), !found.name.isEmpty, !found.type.isEmpty {
                map[found.name] = found.type
            }
            for child in node.namedChildren() { walk(child) }
        }
        walk(body)
        return map
    }

    /// Worth walking even when no properties are known, since `this`/`self` and `TypeName.method()`
    /// calls are still resolvable. The body's provable local bindings are folded into the scope first.
    public func extractCallSites(
        from body: Node?,
        scope: CallSiteScope
    ) -> [CallSite] {
        guard let body else { return [] }
        var sites: [CallSite] = []
        walkForCallSites(body, scope: scope.merging(locals: localBindings(in: body, scope: scope)), into: &sites)
        return sites
    }

    private func walkForCallSites(
        _ node: Node,
        scope: CallSiteScope,
        into sites: inout [CallSite]
    ) {
        if let site = resolveCallSite(node, scope: scope) {
            sites.append(site)
        }
        for child in node.namedChildren() {
            walkForCallSites(child, scope: scope, into: &sites)
        }
    }

    /// Resolves a member call's `receiver` to a ``AcaiCore/CallSite`` using the receiver decision tree
    /// shared by field-name-based grammars: `this.method()` → unqualified self-call; `receiver.method()`
    /// / `this.prop.method()` → resolved against `scope`; a deeper chain where `a`'s type is known but
    /// `b` isn't a property here → deferred `.propertyChain`, resolved post-merge. Grammar-specific
    /// call-node unwrapping stays with the caller.
    public func resolveMemberCall(
        receiver: Node,
        methodName: String,
        grammar: MemberCallGrammar,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        if receiver.nodeType == grammar.selfNodeType {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: location)
        }

        if receiver.nodeType == "identifier" {
            return scope.resolvedCallSite(receiverName: text(receiver), methodName: methodName, location: location)
        }

        guard receiver.nodeType == grammar.memberAccessType,
              let object = receiver.child(byFieldName: "object"),
              let member = receiver.child(byFieldName: grammar.memberField)
        else { return nil }
        let hop = text(member)

        if object.nodeType == grammar.selfNodeType {
            return scope.resolvedCallSite(receiverName: hop, methodName: methodName, location: location)
        }

        // Deeper chain: resolve the head to a type and defer `hop` to the post-merge pass.
        guard object.nodeType == "identifier" else { return nil }
        let headName = text(object)
        let headType = scope.knownProperties[headName]
            ?? (scope.knownTypeNames.contains(headName) ? headName : nil)
        guard let headType else { return nil }
        return CallSite(
            receiver: .propertyChain(headTypeName: headType, hops: [hop]),
            methodName: methodName, location: location
        )
    }
}

/// The grammar node types a language uses for member-call receiver resolution (see
/// ``CallSiteResolving/resolveMemberCall(receiver:methodName:grammar:scope:location:)``).
public struct MemberCallGrammar: Sendable {
    /// The node type of a `this`/`self` expression (e.g. `"this"`).
    public let selfNodeType: String
    /// The node type of a `<self>.<member>` access (e.g. `"field_access"`).
    public let memberAccessType: String
    /// The field name holding the member in that access (e.g. `"field"`).
    public let memberField: String

    public init(selfNodeType: String, memberAccessType: String, memberField: String) {
        self.selfNodeType = selfNodeType
        self.memberAccessType = memberAccessType
        self.memberField = memberField
    }
}
