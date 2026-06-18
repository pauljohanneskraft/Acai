import Testing
@testable import UMLPython
@testable import UMLCore

@Suite("Python: Assignment Tests")
struct PythonAssignmentTests {
    let parser = PythonCodeParser()

    private func assignments(_ source: String, method: String) -> [VariableAssignment] {
        parser.parse(source: source, fileName: "test.py")
            .types.flatMap(\.members).first { $0.name == method }?.assignments ?? []
    }

    @Test func selfAssignmentTargets() {
        let source = """
        class Counter:
            def reset(self):
                self.count = 0
                self.active = True
        """
        let writes = assignments(source, method: "reset")
        #expect(writes.contains { $0.targetName == "count" && $0.value.kind == .numericLiteral })
        #expect(writes.contains { $0.targetName == "active" && $0.value.kind == .booleanLiteral })
    }

    @Test func enumCaseAssignmentClassified() {
        let source = """
        class Light:
            def turn_on(self):
                self.state = Color.RED
        """
        let writes = assignments(source, method: "turn_on")
        let stateWrite = writes.first { $0.targetName == "state" }
        #expect(stateWrite?.value.kind == .enumCase)
        #expect(stateWrite?.value.receiverTypeName == "Color")
    }

    @Test func compoundAssignmentIsExpression() {
        let source = """
        class Counter:
            def bump(self):
                self.count += 1
        """
        let writes = assignments(source, method: "bump")
        let bump = writes.first { $0.targetName == "count" }
        #expect(bump?.op == .compound)
        #expect(bump?.value.kind == .expression)
    }

    @Test func stringAndNoneLiterals() {
        let source = """
        class Box:
            def fill(self):
                self.label = "hello"
                self.payload = None
        """
        let writes = assignments(source, method: "fill")
        #expect(writes.contains { $0.targetName == "label" && $0.value.kind == .stringLiteral })
        #expect(writes.contains { $0.targetName == "payload" && $0.value.kind == .nilLiteral })
    }
}
