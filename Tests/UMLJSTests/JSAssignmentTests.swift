import Testing
@testable import UMLJS
@testable import UMLCore

@Suite("JS/TS Assignment Extraction")
struct JSAssignmentTests {
    let tsParser = JSCodeParser(isTypeScript: true)
    let jsParser = JSCodeParser(isTypeScript: false)

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = tsParser.parse(source: source, fileName: "test.ts")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func qualifiedEnumCaseAssignment() {
        let source = """
        class Loader {
            state: State = State.Idle;
            load(): void {
                this.state = State.Loading;
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.count == 1)
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.targetReceiver == nil)
        #expect(assignments.first?.op == .assign)
        #expect(assignments.first?.value == .init(kind: .enumCase, text: "Loading", receiverTypeName: "State"))
    }

    @Test func literalKinds() {
        let source = """
        class Flags {
            update(): void {
                this.enabled = true;
                this.count = 42;
                this.label = "idle";
                this.token = null;
                this.thing = undefined;
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.booleanLiteral, .numericLiteral, .stringLiteral, .nilLiteral, .nilLiteral])
    }

    @Test func compoundAndIncrementAreCompound() {
        let source = """
        class Counter {
            bump(): void {
                this.count += 1;
                this.count++;
                --this.count;
            }
        }
        """
        let assignments = member("bump", in: source)?.assignments ?? []
        #expect(assignments.count == 3)
        #expect(assignments.allSatisfy { $0.op == .compound })
        #expect(assignments.allSatisfy { $0.targetName == "count" })
    }

    @Test func nonEnumerableValueIsExpression() {
        let source = """
        class Loader {
            load(): void {
                this.state = fetchState();
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.first?.value.kind == .expression)
    }

    @Test func fieldInitializerIsCaptured() {
        let source = """
        class Loader {
            state: State = State.Idle;
            enabled: boolean = false;
            token: string | null = null;
            session = makeSession();
        }
        """
        let artifact = tsParser.parse(source: source, fileName: "test.ts")
        let members = artifact.types[0].members
        #expect(members.first { $0.name == "state" }?.initialValue
            == .init(kind: .enumCase, text: "Idle", receiverTypeName: "State"))
        #expect(members.first { $0.name == "enabled" }?.initialValue?.kind == .booleanLiteral)
        #expect(members.first { $0.name == "token" }?.initialValue?.kind == .nilLiteral)
        #expect(members.first { $0.name == "session" }?.initialValue?.kind == .expression)
    }

    @Test func plainJavaScriptAssignments() {
        let source = """
        class Loader {
            load() {
                this.state = "loading";
                this.retries = 0;
            }
        }
        """
        let artifact = jsParser.parse(source: source, fileName: "test.js")
        let load = artifact.types.first?.members.first { $0.name == "load" }
        let kinds = (load?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.stringLiteral, .numericLiteral])
    }
}
