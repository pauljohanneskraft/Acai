import Testing
@testable import UMLSwift
@testable import UMLCore

@Suite("Swift Assignment Extraction")
struct SwiftAssignmentTests {
    let parser = SwiftCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func implicitEnumCaseAssignment() {
        let source = """
        class Loader {
            var state: State = .idle
            func load() {
                state = .loading
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.count == 1)
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.op == .assign)
        #expect(assignments.first?.value == .init(kind: .enumCase, text: "loading"))
    }

    @Test func qualifiedEnumCaseAndSelfTarget() {
        let source = """
        class Loader {
            var state: State = .idle
            func load() {
                self.state = State.loaded
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.first?.targetName == "state")
        #expect(assignments.first?.targetReceiver == nil)
        #expect(assignments.first?.value == .init(kind: .enumCase, text: "loaded", receiverTypeName: "State"))
    }

    @Test func literalKinds() {
        let source = """
        class Flags {
            func update() {
                enabled = true
                count = 42
                label = "idle"
                ratio = 1.5
                token = nil
            }
        }
        """
        let kinds = (member("update", in: source)?.assignments ?? []).map(\.value.kind)
        #expect(kinds == [.booleanLiteral, .numericLiteral, .stringLiteral, .numericLiteral, .nilLiteral])
    }

    @Test func compoundAssignmentIsCompound() {
        let source = """
        class Counter {
            func bump() {
                count += 1
                total &+= 2
            }
        }
        """
        let assignments = member("bump", in: source)?.assignments ?? []
        #expect(assignments.count == 2)
        #expect(assignments.allSatisfy { $0.op == .compound })
    }

    @Test func nonEnumerableValuesAreExpressions() {
        let source = """
        class Loader {
            func load() {
                state = computeState()
                state = condition ? .first : .second
                state = .loaded(data)
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.count == 3)
        #expect(assignments.allSatisfy { $0.value.kind == .expression })
    }

    @Test func sourceOrderIsPreserved() {
        let source = """
        class Loader {
            func load() {
                state = .loading
                if ok {
                    state = .loaded
                }
                state = .failed
            }
        }
        """
        let texts = (member("load", in: source)?.assignments ?? []).map(\.value.text)
        #expect(texts == ["loading", "loaded", "failed"])
    }

    @Test func propertyInitializerIsCaptured() {
        let source = """
        class Loader {
            var state: State = .idle
            var enabled = false
            var token: String? = nil
            var session = makeSession()
            var computed: Int { 42 }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        let members = artifact.types[0].members
        #expect(members.first { $0.name == "state" }?.initialValue == .init(kind: .enumCase, text: "idle"))
        #expect(members.first { $0.name == "enabled" }?.initialValue?.kind == .booleanLiteral)
        #expect(members.first { $0.name == "token" }?.initialValue?.kind == .nilLiteral)
        #expect(members.first { $0.name == "session" }?.initialValue?.kind == .expression)
        #expect(members.first { $0.name == "computed" }?.initialValue == nil)
    }

    @Test func initializerAssignmentsAreCaptured() {
        let source = """
        class Loader {
            var state: State
            init() {
                state = .idle
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        let ctor = artifact.types[0].members.first { $0.kind == .initializer }
        #expect(ctor?.assignments.first?.value == .init(kind: .enumCase, text: "idle"))
    }

    @Test func globalVariableInitializerIsCaptured() {
        let source = """
        var appMode: Mode = .normal

        func escalate() {
            appMode = .debug
        }
        """
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        #expect(artifact.globalVariables.first?.initialValue == .init(kind: .enumCase, text: "normal"))
        let function = artifact.freestandingFunctions.first { $0.name == "escalate" }
        #expect(function?.assignments.first?.value == .init(kind: .enumCase, text: "debug"))
    }

    @Test func staticReceiverTargetIsKept() {
        let source = """
        class Loader {
            static var shared: State = .idle
            func reset() {
                Loader.shared = .idle
            }
        }
        """
        let assignments = member("reset", in: source)?.assignments ?? []
        #expect(assignments.first?.targetName == "shared")
        #expect(assignments.first?.targetReceiver == "Loader")
    }

    @Test func chainedAssignmentIsExpression() {
        let source = """
        class Loader {
            func load() {
                a = b = .loading
            }
        }
        """
        let assignments = member("load", in: source)?.assignments ?? []
        #expect(assignments.first?.value.kind == .expression)
    }
}
