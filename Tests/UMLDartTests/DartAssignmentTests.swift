import Testing
@testable import UMLDart
@testable import UMLCore

@Suite("Dart Assignment Extraction")
struct DartAssignmentTests {
    let parser = DartCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "test.dart")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func qualifiedEnumCaseAssignment() {
        let source = """
        class Loader {
            LoadState state = LoadState.idle;
            void load() {
                state = LoadState.loading;
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.count == 1)
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.op == .assign)
        #expect(assignments.first?.value == .init(kind: .enumCase, text: "loading", receiverTypeName: "LoadState"))
    }

    @Test func thisQualifiedTargetIsStripped() {
        let source = """
        class Loader {
            void reset() {
                this.state = LoadState.idle;
            }
        }
        """
        let assignments = member("reset", in: source)?.assignments ?? []
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.targetReceiver == nil)
    }

    @Test func literalKinds() {
        let source = """
        class Flags {
            void update() {
                enabled = true;
                count = 42;
                label = "idle";
                token = null;
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.booleanLiteral, .numericLiteral, .stringLiteral, .nilLiteral])
    }

    @Test func interpolatedStringIsExpression() {
        let source = """
        class Loader {
            void update() {
                label = 'idle';
                detail = 'state is $state';
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.stringLiteral, .expression])
    }

    @Test func compoundAndIncrementAreCompound() {
        let source = """
        class Counter {
            void bump() {
                count += 1;
                count++;
                --count;
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
            void load() {
                state = fetchState();
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.first?.value.kind == .expression)
    }

    @Test func fieldInitializerIsCaptured() {
        let source = """
        class Loader {
            LoadState state = LoadState.idle;
            bool enabled = false;
            String? token = null;
            final session = makeSession();
        }
        """
        let artifact = parser.parse(source: source, fileName: "test.dart")
        let members = artifact.types[0].members
        #expect(members.first { $0.name == "state" }?.initialValue
            == .init(kind: .enumCase, text: "idle", receiverTypeName: "LoadState"))
        #expect(members.first { $0.name == "enabled" }?.initialValue?.kind == .booleanLiteral)
        #expect(members.first { $0.name == "token" }?.initialValue?.kind == .nilLiteral)
        #expect(members.first { $0.name == "session" }?.initialValue?.kind == .expression)
    }

    @Test func sourceOrderIsPreserved() {
        let source = """
        class Loader {
            void load() {
                state = LoadState.loading;
                state = LoadState.loaded;
            }
            void fail() {
                state = LoadState.failed;
            }
        }
        """
        let load = member("load", in: source)
        let fail = member("fail", in: source)
        #expect(load?.assignments.map(\.value.text) == ["loading", "loaded"])
        #expect(fail?.assignments.map(\.value.text) == ["failed"])
    }
}
