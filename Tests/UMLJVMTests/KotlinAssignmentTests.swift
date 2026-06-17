import Testing
@testable import UMLJVM
@testable import UMLCore

@Suite("Kotlin Assignment Extraction")
struct KotlinAssignmentTests {
    let parser = KotlinCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "Test.kt")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func qualifiedEnumCaseAssignment() {
        let source = """
        class Loader {
            var state: State = State.IDLE
            fun load() {
                state = State.LOADING
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.count == 1)
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.targetReceiver == nil)
        #expect(assignments.first?.op == .assign)
        #expect(assignments.first?.value == .init(kind: .enumCase, text: "LOADING", receiverTypeName: "State"))
    }

    @Test func thisQualifiedTargetIsStripped() {
        let source = """
        class Loader {
            var state: State = State.IDLE
            fun reset() {
                this.state = State.IDLE
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
            fun update() {
                enabled = true
                count = 42
                label = "idle"
                ratio = 1.5
                token = null
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.booleanLiteral, .numericLiteral, .stringLiteral, .numericLiteral, .nilLiteral])
    }

    @Test func interpolatedStringIsExpression() {
        let source = """
        class Loader {
            fun update() {
                label = "idle"
                detail = "state is $state"
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.stringLiteral, .expression])
    }

    @Test func compoundAndIncrementAreCompound() {
        let source = """
        class Counter {
            fun bump() {
                count += 1
                count++
                --count
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
            fun load() {
                state = fetchState()
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.first?.value.kind == .expression)
        #expect(assignments.first?.value.text == "fetchState()")
    }

    @Test func sourceOrderIsPreserved() {
        let source = """
        class Loader {
            fun load() {
                state = State.LOADING
                if (ok) {
                    state = State.LOADED
                }
                state = State.FAILED
            }
        }
        """
        let texts = (member("load", in: source)?.assignments ?? []).map(\.value.text)
        #expect(texts == ["LOADING", "LOADED", "FAILED"])
    }

    @Test func propertyInitializerIsCaptured() {
        let source = """
        class Loader {
            var state: State = State.IDLE
            var enabled: Boolean = false
            var token: String? = null
            var session = makeSession()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Test.kt")
        let members = artifact.types[0].members
        #expect(members.first { $0.name == "state" }?.initialValue
            == .init(kind: .enumCase, text: "IDLE", receiverTypeName: "State"))
        #expect(members.first { $0.name == "enabled" }?.initialValue?.kind == .booleanLiteral)
        #expect(members.first { $0.name == "token" }?.initialValue?.kind == .nilLiteral)
        #expect(members.first { $0.name == "session" }?.initialValue?.kind == .expression)
    }

    @Test func constructorAssignmentsAreCaptured() {
        let source = """
        class Loader {
            var state: State = State.IDLE
            constructor(eager: Boolean) {
                state = State.LOADING
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Test.kt")
        let ctor = artifact.types[0].members.first { $0.kind == .initializer }
        #expect(ctor?.assignments.first?.value.text == "LOADING")
    }

    @Test func instanceReceiverTargetsAreSkipped() {
        let source = """
        class Loader {
            fun load(other: Loader) {
                other.state = State.LOADING
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.isEmpty)
    }
}
