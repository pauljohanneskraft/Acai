import AcaiCore

// MARK: - CallSiteSyntax

/// One language's answer to "is this node a call, and what does it call?".
///
/// A conformer classifies a single node and holds no mutable state, so a plugin's own collaborator
/// types can hold one — the recursion and scope merging live in ``CallSiteResolver``.
public protocol CallSiteSyntax {

    var context: SourceFileContext { get }

    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite?

    /// Local-variable name → provably-declared type, so calls on locals resolve
    /// (`var x = Foo(); x.method()`). Default: no locals. A language overrides this to recognise its
    /// typed/constructed local declarations, emitting only provable types.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String]
}

extension CallSiteSyntax {

    public func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] { [:] }

    /// Lets a language's ``localBindings(in:scope:)`` write only a per-node recogniser. A later
    /// binding for the same name wins.
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
}

// MARK: - CallSiteResolver

/// Collects a body's call sites, in source (pre-order) order.
public struct CallSiteResolver {

    private let syntax: any CallSiteSyntax

    public init(syntax: any CallSiteSyntax) {
        self.syntax = syntax
    }

    /// Worth walking even when no properties are known, since `this`/`self` and `TypeName.method()`
    /// calls are still resolvable. The body's local bindings are folded into the scope first, which
    /// is why this is two passes.
    public func callSites(in body: Node?, scope: CallSiteScope) -> [CallSite] {
        guard let body else { return [] }
        let merged = scope.merging(locals: syntax.localBindings(in: body, scope: scope))
        var sites: [CallSite] = []
        collect(body, scope: merged, into: &sites)
        return sites
    }

    private func collect(_ node: Node, scope: CallSiteScope, into sites: inout [CallSite]) {
        if let site = syntax.resolveCallSite(node, scope: scope) {
            sites.append(site)
        }
        for child in node.namedChildren() {
            collect(child, scope: scope, into: &sites)
        }
    }
}

// MARK: - MemberReceiver

/// A call's receiver expression, decomposed into the three shapes the shared decision tree knows.
///
/// Grammars disagree on how they spell each one — a field-name grammar nests a member access under
/// `object`/`field` fields, Kotlin nests `navigation_expression`s, Dart flattens the whole call into
/// sibling selectors — so a language answers in these terms and the tree stays one implementation.
public enum MemberReceiver {

    /// `this` / `self`.
    case selfExpression

    /// A bare name: the `a` of `a.method()`.
    case name(String)

    /// `<object>.<hop>`: the receiver is itself a member access, as in the `a.b` of `a.b.method()`.
    case memberAccess(object: Node, hop: String)
}

/// One grammar's answer to "what shape is this receiver expression?".
public protocol MemberReceiverSyntax {

    func receiver(_ node: Node) -> MemberReceiver?
}

/// Receiver decomposition for grammars that expose a member access through `object` and a named
/// member field — Java's `field_access`, JS's `member_expression`, Python's `attribute`.
struct FieldNameReceiverSyntax: MemberReceiverSyntax {

    let context: SourceFileContext
    let grammar: MemberCallGrammar

    func receiver(_ node: Node) -> MemberReceiver? {
        if let selfNodeType = grammar.selfNodeType, node.nodeType == selfNodeType {
            return .selfExpression
        }
        if node.nodeType == "identifier" {
            let text = node.text(in: context)
            return text == grammar.selfIdentifier ? .selfExpression : .name(text)
        }
        guard node.nodeType == grammar.memberAccessType,
              let object = node.child(byFieldName: "object"),
              let member = node.child(byFieldName: grammar.memberField)
        else { return nil }
        return .memberAccess(object: object, hop: member.text(in: context))
    }
}

// MARK: - MemberCallResolver

/// The receiver decision tree every field-name-and-chain grammar shares: `this.method()` →
/// unqualified self-call; `receiver.method()` / `this.prop.method()` → resolved against the scope; a
/// deeper chain whose head resolves but whose hop doesn't → deferred `.propertyChain`.
///
/// Grammar-specific call-node unwrapping stays with the caller — `receiver` arrives unwrapped.
public struct MemberCallResolver {

    private let syntax: any MemberReceiverSyntax

    public init(syntax: any MemberReceiverSyntax) {
        self.syntax = syntax
    }

    /// Field-name grammars get the shared decomposition rather than writing one.
    public init(context: SourceFileContext, grammar: MemberCallGrammar) {
        self.init(syntax: FieldNameReceiverSyntax(context: context, grammar: grammar))
    }

    public func callSite(
        receiver: Node,
        methodName: String,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        guard let shape = syntax.receiver(receiver) else { return nil }
        return callSite(receiver: shape, methodName: methodName, scope: scope, location: location)
    }

    /// The entry point for a grammar that flattens a call into siblings, where the receiver is not a
    /// single node the syntax could decompose on its own.
    public func callSite(
        receiver: MemberReceiver,
        methodName: String,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        switch receiver {
        case .selfExpression:
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: location)
        case .name(let name):
            return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: location)
        case .memberAccess(let object, let hop):
            return chainedCallSite(
                object: object, hop: hop, methodName: methodName, scope: scope, location: location
            )
        }
    }

    /// A chain off `this` is just a call on that property; a chain off a resolvable head defers the
    /// hop to the post-merge pass. Anything deeper than one hop stays dropped.
    private func chainedCallSite(
        object: Node,
        hop: String,
        methodName: String,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        switch syntax.receiver(object) {
        case .selfExpression:
            return scope.resolvedCallSite(receiverName: hop, methodName: methodName, location: location)
        case .name(let headName):
            let headType = scope.knownProperties[headName]
                ?? (scope.knownTypeNames.contains(headName) ? headName : nil)
            guard let headType else { return nil }
            return CallSite(
                receiver: .propertyChain(headTypeName: headType, hops: [hop]),
                methodName: methodName, location: location
            )
        case .memberAccess, nil:
            return nil
        }
    }
}

/// The grammar node types a language uses for member-call receiver resolution.
public struct MemberCallGrammar: Sendable {
    /// The node type of a `this`/`self` expression (e.g. `"this"`), where the grammar has a distinct
    /// one.
    public let selfNodeType: String?
    /// The identifier text naming the enclosing instance, where the grammar spells it as a plain
    /// identifier instead (Python's `self`).
    public let selfIdentifier: String?
    /// The node type of a `<object>.<member>` access (e.g. `"field_access"`).
    public let memberAccessType: String
    /// The field name holding the member in that access (e.g. `"field"`).
    public let memberField: String

    public init(
        selfNodeType: String? = nil,
        selfIdentifier: String? = nil,
        memberAccessType: String,
        memberField: String
    ) {
        self.selfNodeType = selfNodeType
        self.selfIdentifier = selfIdentifier
        self.memberAccessType = memberAccessType
        self.memberField = memberField
    }
}
