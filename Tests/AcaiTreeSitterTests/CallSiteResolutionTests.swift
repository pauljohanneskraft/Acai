import AcaiCore
import Testing
@testable import AcaiTreeSitter

/// A minimal `CallSiteSyntax` over Java's `method_invocation`: enough grammar knowledge to reach the
/// shared decision tree, and nothing a plugin would add on top.
private struct JavaCallSyntax: CallSiteSyntax {

    let context: SourceFileContext
    private let members: MemberCallResolver

    init(context: SourceFileContext) {
        self.context = context
        self.members = MemberCallResolver(
            context: context,
            grammar: MemberCallGrammar(
                selfNodeType: "this", memberAccessType: "field_access", memberField: "field"))
    }

    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "method_invocation",
              let methodName = node.child(byFieldName: "name")?.text(in: context)
        else { return nil }
        let location = node.location(in: context)
        guard let receiver = node.child(byFieldName: "object") else {
            return scope.bareCall(named: methodName, implicitSelf: true, location: location)
        }
        return members.callSite(
            receiver: receiver, methodName: methodName, scope: scope, location: location)
    }

    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "local_variable_declaration",
                  let type = node.child(byFieldName: "type")?.text(in: self.context),
                  let name = node.firstChild(withType: "variable_declarator")?
                      .child(byFieldName: "name")?.text(in: self.context)
            else { return nil }
            return (name, type)
        }
    }
}

@Suite("Call Site Resolution")
struct CallSiteResolutionTests {

    private let scope = CallSiteScope(
        knownProperties: ["repository": "Repository", "alpha": "Alpha"],
        knownTypeNames: ["Service", "Repository", "Alpha"])

    private func sites(in source: String, method: String = "run") throws -> [CallSite] {
        let fixture = try #require(JavaFixture(source))
        let body = try #require(fixture.methodBody(method))
        return CallSiteResolver(syntax: JavaCallSyntax(context: fixture.context))
            .callSites(in: body, scope: scope)
    }

    @Test("A typed stored property, this.property and a declared type each resolve to that type")
    func provableReceiversResolve() throws {
        let sites = try sites(in: """
        class Service {
            void run() {
                repository.save();
                this.repository.save();
                Repository.create();
            }
        }
        """)
        #expect(sites.map(\.receiver) == [
            .type("Repository"), .type("Repository"), .type("Repository")
        ])
        #expect(sites.map(\.methodName) == ["save", "save", "create"])
        // Pre-order, so the sites arrive in source order with their own lines.
        #expect(sites.compactMap { $0.location?.line } == [3, 4, 5])
    }

    @Test("A local initialised from a construction resolves, because local bindings fold in first")
    func localBindingsAreMergedBeforeTheWalk() throws {
        let sites = try sites(in: """
        class Service {
            void run() {
                Repository other = new Repository();
                other.save();
            }
        }
        """)
        #expect(sites.map(\.receiver) == [.type("Repository")])
        #expect(sites.map(\.methodName) == ["save"])
        let location = try #require(sites.first?.location)
        #expect(location.filePath == "Fixture.java")
        #expect(location.line == 4)
        #expect(location.endLine == 4)
        // No column assertion: tree-sitter reports a byte offset into UTF-16 source, so
        // `Node.location(in:)` returns twice the real column for an ASCII line.
        #expect(location.column > 0)
    }

    @Test("An unknown lowercase receiver is dropped; an unknown capitalised one is deferred")
    func unprovableReceiversAreDroppedOrDeferred() throws {
        let sites = try sites(in: """
        class Service {
            void run() {
                mystery.save();
                Elsewhere.create();
            }
        }
        """)
        #expect(sites.map(\.receiver) == [.unresolvedTypeName("Elsewhere")])
    }

    @Test("A chain off a resolvable head defers its hop; a deeper chain is dropped")
    func chainedReceiversDeferOneHop() throws {
        let sites = try sites(in: """
        class Service {
            void run() {
                alpha.beta.save();
                alpha.beta.gamma.save();
            }
        }
        """)
        #expect(sites.map(\.receiver) == [.propertyChain(headTypeName: "Alpha", hops: ["beta"])])
    }

    @Test("A bare call with no receiver dispatches to the enclosing type")
    func bareCallIsSelfDispatch() throws {
        let sites = try sites(in: """
        class Service {
            void run() {
                helper();
            }
        }
        """)
        #expect(sites.map(\.receiver) == [.selfDispatch])
        #expect(sites.map(\.methodName) == ["helper"])
    }

    @Test("A body the grammar never produced yields no call sites")
    func absentBodyYieldsNothing() throws {
        let fixture = try #require(JavaFixture("class Service {}"))
        let resolver = CallSiteResolver(syntax: JavaCallSyntax(context: fixture.context))
        #expect(resolver.callSites(in: nil, scope: scope).isEmpty)
    }

    /// `MemberReceiver` carries a `Node`, so it is not `Equatable`; this is what a test compares.
    private func label(of receiver: MemberReceiver?) -> String {
        switch receiver {
        case .selfExpression: "self"
        case .name(let name): "name(\(name))"
        case .memberAccess(_, let hop): "memberAccess(\(hop))"
        case nil: "none"
        }
    }

    @Test("The shared decomposition reads `this` and a bare name without a grammar node of its own")
    func fieldNameReceiverSyntaxDecomposesTheThreeShapes() throws {
        let fixture = try #require(JavaFixture("""
        class Service {
            void run() {
                this.repository.save();
            }
        }
        """))
        let syntax = FieldNameReceiverSyntax(
            context: fixture.context,
            grammar: MemberCallGrammar(
                selfNodeType: "this", memberAccessType: "field_access", memberField: "field"))
        let access = try #require(fixture.firstNode(ofType: "field_access"))
        guard case .memberAccess(let object, let hop) = try #require(syntax.receiver(access)) else {
            Issue.record("expected a member access")
            return
        }
        #expect(hop == "repository")
        #expect(label(of: syntax.receiver(object)) == "self")
        let name = try #require(fixture.firstNode(ofType: "identifier"))
        #expect(label(of: syntax.receiver(name)) == "name(Service)")
        #expect(label(of: syntax.receiver(try #require(fixture.firstNode(ofType: "class_body")))) == "none")
    }
}
