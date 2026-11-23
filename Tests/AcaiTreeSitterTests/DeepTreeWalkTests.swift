import AcaiCore
import Testing
@testable import AcaiTreeSitter

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

/// Each walk runs on a cooperative-pool-sized 512 KB stack, where a recursive walk would overflow.
@Suite("Deep tree walks")
struct DeepTreeWalkTests {

    static let depth = 5_000

    let poolSizedStack = LargeStackRunner(stackSize: 512 * 1024)

    let deeplyNestedSource: String = {
        let depth = DeepTreeWalkTests.depth
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
    }()

    /// Parses on the small stack too, since a `Node` cannot leave the thread; `nil` if the parse failed.
    private func measuringDeepTree<Value: Sendable>(
        _ measure: @escaping @Sendable (JavaFixture) -> Value
    ) async -> Value? {
        let source = deeplyNestedSource
        return await poolSizedStack.run { JavaFixture(source).map(measure) }
    }

    @Test func walkPreorderVisitsEveryLevel() async throws {
        let visited = try #require(await measuringDeepTree { fixture in
            var visited = 0
            fixture.root.walkPreorder { _ in visited += 1 }
            return visited
        })
        #expect(visited > Self.depth)
    }

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
        let names = try #require(await measuringDeepTree { fixture in
            TypeNamePrepass(declarationNodeTypes: ["class_declaration"])
                .names(in: fixture.root) { $0.child(byFieldName: "name")?.text(in: fixture.context) }
                .sorted()
        })
        #expect(names == ["Deep"])
    }

    @Test func parseDiagnosticsCollectorWalksTheWholeTree() async throws {
        let diagnostics = try #require(await measuringDeepTree { fixture in
            ParseDiagnosticsCollector(context: fixture.context).diagnostics(in: fixture.root)
        })
        #expect(diagnostics.isEmpty)
    }

    @Test func callSiteResolverWalksTheWholeBody() async throws {
        let names = try #require(await measuringDeepTree { fixture in
            CallSiteResolver(syntax: DeepCallSiteSyntax(context: fixture.context))
                .callSites(in: fixture.methodBody("run"), scope: CallSiteScope(knownTypeNames: ["Deep"]))
                .map(\.methodName)
        })
        #expect(names == ["hop"])
    }

    @Test func assignmentResolverWalksTheWholeBody() async throws {
        let assignments = try #require(await measuringDeepTree { fixture in
            AssignmentResolver(syntax: DeepAssignmentSyntax(context: fixture.context))
                .assignments(in: fixture.methodBody("run"))
        })
        #expect(assignments.isEmpty)
    }

    @Test func fieldReadResolverWalksTheWholeBody() async throws {
        let names = try #require(await measuringDeepTree { fixture in
            FieldReadResolver(context: fixture.context, identifierTypes: ["identifier"])
                .reads(in: fixture.methodBody("run"), knownProperties: ["seed"])
                .map(\.name)
        })
        #expect(names == ["seed"])
    }

    @Test func cyclomaticComplexityWalksTheWholeBody() async throws {
        let complexity = try #require(await measuringDeepTree { fixture in
            fixture.methodBody("run")?.cyclomaticComplexity(branchKinds: ["if_statement"])
        })
        #expect(complexity == 1)
    }

    @Test func referencedTypeNamesWalksTheWholeBody() async throws {
        let names = try #require(await measuringDeepTree { fixture in
            fixture.methodBody("run")?.referencedTypeNames(in: fixture.context) ?? []
        })
        #expect(names.contains("Deep"))
    }
}
