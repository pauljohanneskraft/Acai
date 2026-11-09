import AcaiCore
import Testing
@testable import AcaiTreeSitter

/// A minimal ``CallSiteSyntax`` over Java's `method_invocation`, with one local-binding recogniser
/// so ``CallSiteSyntax/collectLocalBindings(in:binding:)`` is walked too.
private struct DeepCallSiteSyntax: CallSiteSyntax {

    let context: SourceFileContext

    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "method_invocation",
              let name = node.child(byFieldName: "name")
        else { return nil }
        return CallSite(
            receiver: .free, methodName: name.text(in: context), location: node.location(in: context))
    }

    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "local_variable_declaration",
                  let type = node.child(byFieldName: "type"),
                  let declarator = node.firstChild(withType: "variable_declarator"),
                  let name = declarator.child(byFieldName: "name")
            else { return nil }
            return (name.text(in: context), type.text(in: context))
        }
    }
}

private struct DeepAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext

    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        guard node.nodeType == "assignment_expression",
              let left = node.child(byFieldName: "left"),
              let right = node.child(byFieldName: "right")
        else { return nil }
        return VariableAssignment(
            targetName: left.text(in: context), targetReceiver: nil, op: .assign,
            value: VariableAssignment.Value(kind: .expression, text: right.text(in: context)),
            location: node.location(in: context))
    }
}

/// Every shared node walk is iterative, so none of them overflows the stack on a tree nested
/// thousands of levels deep (#524).
///
/// Each walk runs on a thread with a **512 KB** stack — the size a cooperative-pool thread gets in
/// production, and the stack the crash happened on. Running them on whatever stack the test runner
/// provides proves nothing: a recursive walk survives 5,000 levels there, so the fix would not be
/// held to anything. Tree-sitter's own parser is iterative, so the tree itself builds on 512 KB.
///
/// A walk's result has to leave the thread, and `Node` is a handle into a tree that does not, so
/// each case parses inside the closure and returns only what it measured.
@Suite("Deep tree walks")
struct DeepTreeWalkTests {

    static let depth = 5_000

    /// A cooperative-pool thread's stack size, so these fail the way production failed.
    static let poolSizedStack = LargeStackRunner(stackSize: 512 * 1024)

    /// `((((…1…))))` as the initialiser of a local, inside a method, inside a class.
    private static func deeplyNestedSource(depth: Int) -> String {
        let nested = String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
        return """
        class Deep {
            void run() {
                int seed = 0;
                Deep local = new Deep();
                int value = \(nested);
                local.hop();
            }
        }
        """
    }

    /// Parses the deep fixture on the small-stack thread and hands `measure` its tree. A `nil`
    /// result means the fixture itself failed to parse, which each case reports as a failure rather
    /// than passing on an empty measurement.
    private static func measuringDeepTree<Value: Sendable>(
        _ measure: @escaping @Sendable (JavaFixture) -> Value
    ) async -> Value? {
        let source = deeplyNestedSource(depth: depth)
        return await poolSizedStack.run { JavaFixture(source).map(measure) }
    }

    @Test func walkPreorderVisitsEveryLevel() async throws {
        let visited = try #require(await Self.measuringDeepTree { fixture in
            var visited = 0
            fixture.root.walkPreorder { _ in visited += 1 }
            return visited
        })
        #expect(visited > Self.depth)
    }

    /// Pre-order, not mirrored: the explicit stack pushes children in reverse so the left-most is
    /// popped first. A walk that visited siblings backwards would still terminate, so order is
    /// asserted rather than assumed.
    @Test func walkPreorderVisitsSiblingsInSourceOrder() throws {
        let fixture = try #require(JavaFixture("class A { void one() {} void two() {} void three() {} }"))
        var names: [String] = []
        fixture.root.walkNamedPreorder { node in
            guard node.nodeType == "method_declaration",
                  let name = node.child(byFieldName: "name") else { return }
            names.append(name.text(in: fixture.context))
        }
        #expect(names == ["one", "two", "three"])
    }

    @Test func typeNamePrepassReachesTheDeclaration() async throws {
        let names = try #require(await Self.measuringDeepTree { fixture in
            TypeNamePrepass(declarationNodeTypes: ["class_declaration"])
                .names(in: fixture.root) { $0.child(byFieldName: "name")?.text(in: fixture.context) }
                .sorted()
        })
        #expect(names == ["Deep"])
    }

    @Test func parseDiagnosticsCollectorWalksTheWholeTree() async throws {
        let diagnostics = try #require(await Self.measuringDeepTree { fixture in
            ParseDiagnosticsCollector(context: fixture.context).diagnostics(in: fixture.root)
        })
        #expect(diagnostics.isEmpty)
    }

    @Test func callSiteResolverWalksTheWholeBody() async throws {
        let names = try #require(await Self.measuringDeepTree { fixture in
            CallSiteResolver(syntax: DeepCallSiteSyntax(context: fixture.context))
                .callSites(in: fixture.methodBody("run"), scope: CallSiteScope(knownTypeNames: ["Deep"]))
                .map(\.methodName)
        })
        #expect(names == ["hop"])
    }

    @Test func assignmentResolverWalksTheWholeBody() async throws {
        let assignments = try #require(await Self.measuringDeepTree { fixture in
            AssignmentResolver(syntax: DeepAssignmentSyntax(context: fixture.context))
                .assignments(in: fixture.methodBody("run"))
        })
        #expect(assignments.isEmpty)
    }

    @Test func fieldReadResolverWalksTheWholeBody() async throws {
        let names = try #require(await Self.measuringDeepTree { fixture in
            FieldReadResolver(context: fixture.context, identifierTypes: ["identifier"])
                .reads(in: fixture.methodBody("run"), knownProperties: ["seed"])
                .map(\.name)
        })
        #expect(names == ["seed"])
    }

    @Test func cyclomaticComplexityWalksTheWholeBody() async throws {
        let complexity = try #require(await Self.measuringDeepTree { fixture in
            fixture.methodBody("run")?.cyclomaticComplexity(branchKinds: ["if_statement"])
        })
        #expect(complexity == 1)
    }

    @Test func referencedTypeNamesWalksTheWholeBody() async throws {
        let names = try #require(await Self.measuringDeepTree { fixture in
            fixture.methodBody("run")?.referencedTypeNames(in: fixture.context) ?? []
        })
        #expect(names.contains("Deep"))
    }
}
