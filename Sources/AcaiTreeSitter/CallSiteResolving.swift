import Foundation
import AcaiCore

// MARK: - CallSiteScope

/// The statically-known context used to resolve a method call's receiver to a type.
///
/// Resolution stays deliberately conservative — a call site is only captured when its
/// receiver is *provably* a known type: a typed stored property, an explicit `this`/`self`
/// (a call on the enclosing instance), or a `TypeName.method()` where `TypeName` is a
/// declared type. Anything else (locals, parameters, external/stdlib receivers) is dropped
/// so the resulting sequence diagrams keep their near-zero-false-edge guarantee.
public struct CallSiteScope: Sendable {
    /// `propertyName: typeName` for the enclosing type's stored properties — only those with a
    /// determinable type (call-site resolution needs the type).
    public var knownProperties: [String: String]
    /// Simple names of types declared in the current file (for `TypeName.method()`).
    public var knownTypeNames: Set<String>
    /// Names of **all** the enclosing type's stored properties, including untyped ones (e.g. Python's
    /// `self.x = …`). Field-read capture filters by name only, so it needs the full set — not just the
    /// typed subset in ``knownProperties``. Defaults to `knownProperties`' keys when unspecified.
    public var knownPropertyNames: Set<String>
    /// `methodName: returnTypeName` for the enclosing type's own methods (unambiguous overloads
    /// only), so a local initialized from a same-type method call (`let x = compute()`) can have its
    /// type inferred the same way a direct construction already does (RC-I).
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

    /// Resolves a single-identifier receiver (`receiver.method()`) to a ``AcaiCore/CallSite``:
    /// a typed stored property resolves to its declared type; a name matching a known type is
    /// treated as a static/`TypeName.method()` call; a capitalised name matching neither is deferred
    /// (`.unresolvedTypeName`) — possibly a type declared elsewhere in the project, resolved
    /// post-merge by `CodeArtifact.resolvingCallSiteReceivers()`. Returns `nil` for anything else not
    /// provably resolvable (locals, parameters, lowercase external receivers).
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

    /// A copy of this scope with `locals` overlaid onto `knownProperties` (a local shadows a same-named
    /// stored property). Leaves `knownPropertyNames` — the field-read set — untouched, since a local is
    /// not a field. Returns `self` unchanged when there are no locals.
    public func merging(locals: [String: String]) -> CallSiteScope {
        guard !locals.isEmpty else { return self }
        var copy = self
        copy.knownProperties = knownProperties.merging(locals) { _, local in local }
        return copy
    }

    /// A copy of this scope with each parameter's provable declared type overlaid onto
    /// `knownProperties`, so `param.method()` resolves the same way a typed stored property does.
    /// Parameters shadow same-named properties, mirroring ``merging(locals:)``; delegates to it since
    /// the overlay semantics are identical.
    public func merging(parameters: [Parameter]) -> CallSiteScope {
        let map = Dictionary(
            parameters.compactMap { parameter in parameter.type.map { (parameter.internalName, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
        return merging(locals: map)
    }

    /// Resolves a bare `foo()` with no explicit receiver. Skipped when `name` is a known type (it is a
    /// construction `Foo()`, not a call). `implicitSelf` tags it `.selfDispatch` — the call-graph
    /// builder resolves that against the enclosing type first, then falls back to a free function of
    /// the same name — for languages with an implicit receiver; otherwise `.free` (e.g. JS, which has
    /// no implicit `this`, so a bare call is always a free/imported function).
    public func bareCall(named name: String, implicitSelf: Bool, location: SourceLocation?) -> CallSite? {
        guard !knownTypeNames.contains(name) else { return nil }
        return CallSite(receiver: implicitSelf ? .selfDispatch : .free, methodName: name, location: location)
    }
}

// MARK: - CallSiteResolving

/// Opt-in protocol for extractors that support call-site resolution.
///
/// Not every language needs call-site extraction (e.g. Dart does not).
/// This protocol adds the capability by requiring a single method
/// ``resolveCallSite(_:knownProperties:)`` and providing the recursive
/// walk infrastructure in the extension.
public protocol CallSiteResolving: TreeSitterExtracting {

    /// Resolves a single AST node to a ``AcaiCore/CallSite`` if it
    /// represents a statically-resolvable method call (on a known property,
    /// on `this`/`self`, or on a known type).
    ///
    /// Return `nil` for nodes that are not relevant call
    /// expressions, or whose receiver cannot be provably resolved.
    func resolveCallSite(
        _ node: Node,
        scope: CallSiteScope
    ) -> CallSite?

    /// Local-variable name → provably-declared type, collected from a method/function body so calls on
    /// locals resolve (`var x = Foo(); x.method()`). Default: no locals. A language overrides this to
    /// recognise its typed/constructed local declarations, emitting only *provable* types (an explicit
    /// annotation, a direct construction, or — via `scope.knownMethodReturnTypes` — a same-type method
    /// call with an unambiguous return type) to keep resolution certain.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String]
}

// MARK: - CallSiteResolving Default Implementations

extension CallSiteResolving {

    public func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] { [:] }

    /// Recursively collects local bindings by applying `binding` to every node in `body`; a language's
    /// ``localBindings(in:)`` uses this so it only writes a per-node recogniser, not the traversal.
    /// A later binding for the same name wins (approximates last-declaration-wins without block scopes).
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

    /// Extracts call sites from a body node using the statically-known ``CallSiteScope``.
    ///
    /// Walks the AST recursively, calling ``resolveCallSite(_:scope:)`` on each node.
    /// Unlike property-only resolution, this is worth walking even when no properties are
    /// known, because `this`/`self` and `TypeName.method()` calls are still resolvable.
    /// The body's provable local bindings are folded into the scope first so calls on locals resolve.
    public func extractCallSites(
        from body: Node?,
        scope: CallSiteScope
    ) -> [CallSite] {
        guard let body else { return [] }
        var sites: [CallSite] = []
        walkForCallSites(body, scope: scope.merging(locals: localBindings(in: body, scope: scope)), into: &sites)
        return sites
    }

    /// Recursively walks AST nodes, collecting resolved call sites.
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
    /// shared by field-name-based grammars: `this.method()` → an unqualified self-call;
    /// `receiver.method()` and `this.prop.method()` → resolved against `scope`; a deeper chain
    /// (`a.b.method()` where `a`'s type is known but `b` isn't a property of *this* file's types) →
    /// deferred (`.propertyChain`), resolved post-merge by walking `b`'s declared type on `a`'s type
    /// through the full project type graph. The grammar-specific call-node unwrapping (finding the
    /// receiver node and method name) stays with the caller.
    public func resolveMemberCall(
        receiver: Node,
        methodName: String,
        grammar: MemberCallGrammar,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        // Pattern: this.method(args) — a direct call on the enclosing instance.
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

        // Pattern: this.prop.method(args) — a direct property access already resolves in-file.
        if object.nodeType == grammar.selfNodeType {
            return scope.resolvedCallSite(receiverName: hop, methodName: methodName, location: location)
        }

        // A deeper chain (`model.diagrams.method()`): resolve the chain's head (`model`) to a type
        // and defer `hop` (`diagrams`) to the post-merge pass.
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
