import AcaiCore

// MARK: - CallSiteSyntax

/// What the shared call-site walk needs to know about one language: how to read the file, and how
/// to turn a single node into a `CallSite` when that node is a call.
///
/// Deliberately narrow — the recursion, the scope merging and the receiver decision tree are all
/// shared code that consumes this, never per-language. A conformer is a stateless value, so a
/// collaborator type can hold one; it does not have to *be* the extractor.
public protocol CallSiteSyntax {

    var context: SourceFileContext { get }

    /// Resolves one node to a `CallSite` if it is a call this language can classify. Returning
    /// `nil` is the normal case — the walk visits every node.
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite?

    /// Local-variable name → provably-declared type, collected from a body so calls on locals
    /// resolve (`var x = Foo(); x.method()`). Default: no locals. A language overrides this to
    /// recognise its typed/constructed local declarations, emitting only provable types.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String]
}

extension CallSiteSyntax {

    public func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] { [:] }

    /// A language's ``localBindings(in:scope:)`` uses this so it only writes a per-node recogniser,
    /// not the traversal. A later binding for the same name wins.
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

/// Walks a member body and collects its call sites, in source (pre-order) order.
///
/// The counterpart of ``FieldReadResolver``: a value holding the file and one injected
/// per-language ``CallSiteSyntax``, so anything that needs a body's call sites can own one.
public struct CallSiteResolver {

    private let syntax: any CallSiteSyntax

    public init(syntax: any CallSiteSyntax) {
        self.syntax = syntax
    }

    /// Worth walking even when no properties are known, since `this`/`self` and `TypeName.method()`
    /// calls are still resolvable. The body's provable local bindings are folded into the scope
    /// first, which is why this is two passes and not one.
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

/// The receiver decision tree shared by field-name-based grammars: `this.method()` → unqualified
/// self-call; `receiver.method()` / `this.prop.method()` → resolved against the scope; a deeper
/// chain where `a`'s type is known but `b` isn't a property here → deferred `.propertyChain`,
/// resolved post-merge.
///
/// Grammar-specific call-node unwrapping stays with the caller — this receives an
/// already-unwrapped receiver node.
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

        // Deeper chain: resolve the head to a type and defer `hop` to the post-merge pass.
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

/// The grammar node types a language uses for member-call receiver resolution (see
/// ``MemberCallResolver``).
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
