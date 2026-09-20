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

// MARK: - MemberCallResolver

/// The receiver decision tree for field-name-based grammars: `this.method()` → unqualified
/// self-call; `receiver.method()` / `this.prop.method()` → resolved against the scope; a deeper
/// chain whose head resolves but whose hop doesn't → deferred `.propertyChain`.
///
/// Grammar-specific call-node unwrapping stays with the caller — `receiver` arrives unwrapped.
public struct MemberCallResolver {

    private let context: SourceFileContext
    private let grammar: MemberCallGrammar

    public init(context: SourceFileContext, grammar: MemberCallGrammar) {
        self.context = context
        self.grammar = grammar
    }

    public func callSite(
        receiver: Node,
        methodName: String,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        if receiver.nodeType == grammar.selfNodeType {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: location)
        }

        if receiver.nodeType == "identifier" {
            return scope.resolvedCallSite(
                receiverName: receiver.text(in: context), methodName: methodName, location: location
            )
        }

        guard receiver.nodeType == grammar.memberAccessType,
              let object = receiver.child(byFieldName: "object"),
              let member = receiver.child(byFieldName: grammar.memberField)
        else { return nil }
        let hop = member.text(in: context)

        if object.nodeType == grammar.selfNodeType {
            return scope.resolvedCallSite(receiverName: hop, methodName: methodName, location: location)
        }

        guard object.nodeType == "identifier" else { return nil }
        let headName = object.text(in: context)
        let headType = scope.knownProperties[headName]
            ?? (scope.knownTypeNames.contains(headName) ? headName : nil)
        guard let headType else { return nil }
        return CallSite(
            receiver: .propertyChain(headTypeName: headType, hops: [hop]),
            methodName: methodName, location: location
        )
    }
}

/// The grammar node types a language uses for member-call receiver resolution.
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
