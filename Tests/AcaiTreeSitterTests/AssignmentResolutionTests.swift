import AcaiCore
import Testing
@testable import AcaiTreeSitter

extension LiteralNodeTypes {

    static let java = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["decimal_integer_literal", "decimal_floating_point_literal"],
        string: ["string_literal"],
        nilLiteral: ["null_literal"])
}

/// A minimal `AssignmentSyntax` over Java's `assignment_expression`.
private struct JavaAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext
    private let literals: LiteralClassifier

    init(context: SourceFileContext) {
        self.context = context
        self.literals = LiteralClassifier(context: context, literals: .java)
    }

    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        guard node.nodeType == "assignment_expression",
              let left = node.child(byFieldName: "left"),
              let right = node.child(byFieldName: "right"),
              let target = left.text(in: context).assignmentTarget
        else { return nil }
        let value = literals.value(of: right)
            ?? right.trimmedText(in: context).enumCaseValue
            ?? VariableAssignment.Value(kind: .expression, text: right.expressionSnippet(in: context))
        return VariableAssignment(
            targetName: target.name, targetReceiver: target.receiver, op: .assign,
            value: value, location: node.location(in: context))
    }
}

@Suite("Assignment Resolution")
struct AssignmentResolutionTests {

    private func assignments(in source: String, method: String = "run") throws -> [VariableAssignment] {
        let fixture = try #require(JavaFixture(source))
        let body = try #require(fixture.methodBody(method))
        return AssignmentResolver(syntax: JavaAssignmentSyntax(context: fixture.context))
            .assignments(in: body)
    }

    @Test("Each literal kind is classified from the node-type table, in source order")
    func literalKindsAreClassified() throws {
        let assignments = try assignments(in: """
        class Service {
            void run() {
                count = 1;
                label = "idle";
                flag = true;
                missing = null;
                computed = count + 1;
                state = Kind.LOADING;
            }
        }
        """)
        #expect(assignments.map(\.targetName) == [
            "count", "label", "flag", "missing", "computed", "state"
        ])
        #expect(assignments.map(\.value.kind) == [
            .numericLiteral, .stringLiteral, .booleanLiteral, .nilLiteral, .expression, .enumCase
        ])
        #expect(assignments.map(\.value.text) == [
            "1", "\"idle\"", "true", "null", "count + 1", "LOADING"
        ])
        #expect(assignments.last?.value.receiverTypeName == "Kind")
    }

    @Test("A `this.` target is stripped and a `Type.` target is kept")
    func targetReceiversAreNormalised() throws {
        let assignments = try assignments(in: """
        class Service {
            void run() {
                this.count = 1;
                Service.shared = 2;
            }
        }
        """)
        #expect(assignments.map(\.targetName) == ["count", "shared"])
        #expect(assignments.map(\.targetReceiver) == [nil, "Service"])
        #expect(assignments.compactMap { $0.location?.line } == [3, 4])
    }

    @Test("A target that is neither a name nor a one-hop access is dropped")
    func unrecognisedTargetsAreDropped() throws {
        let assignments = try assignments(in: """
        class Service {
            void run() {
                this.inner.count = 1;
                values[0] = 2;
                lower.count = 3;
            }
        }
        """)
        #expect(assignments.isEmpty)
    }

    @Test("An interpolation child downgrades a string to an opaque expression")
    func interpolatedStringsAreNotFixedStates() throws {
        let fixture = try #require(JavaFixture("""
        class Service {
            void run() {
                label = "idle";
            }
        }
        """))
        let literal = try #require(fixture.firstNode(ofType: "string_literal"))
        let plain = LiteralClassifier(
            context: fixture.context, literals: .java)
        #expect(plain.value(of: literal)?.kind == .stringLiteral)

        var interpolating = LiteralNodeTypes.java
        // Java has no interpolation; `string_fragment` stands in for the child type a language that
        // does would list, so the branch is covered without a second grammar.
        interpolating.interpolationChildTypes = ["string_fragment"]
        let classifier = LiteralClassifier(context: fixture.context, literals: interpolating)
        #expect(classifier.value(of: literal)?.kind == .expression)
    }

    @Test("An unclassifiable right-hand side is recorded as one elided line")
    func longExpressionsAreElided() throws {
        let fixture = try #require(JavaFixture("""
        class Service {
            void run() {
                total = first
                    + second;
            }
        }
        """))
        let right = try #require(
            fixture.firstNode(ofType: "assignment_expression")?.child(byFieldName: "right"))
        let snippet = right.expressionSnippet(in: fixture.context)
        #expect(!snippet.contains("\n"))
        #expect(snippet.hasPrefix("first"))
        #expect(snippet.hasSuffix("+ second"))

        let long = String(repeating: "a", count: 200)
        let wide = try #require(JavaFixture("class S { void run() { total = \(long); } }"))
        let elided = try #require(
            wide.firstNode(ofType: "assignment_expression")?
                .child(byFieldName: "right")?.expressionSnippet(in: wide.context))
        #expect(elided.count == 80)
        #expect(elided.hasSuffix("..."))
    }

    @Test("A body the grammar never produced yields no assignments")
    func absentBodyYieldsNothing() throws {
        let fixture = try #require(JavaFixture("class Service {}"))
        let resolver = AssignmentResolver(syntax: JavaAssignmentSyntax(context: fixture.context))
        #expect(resolver.assignments(in: nil).isEmpty)
    }
}
