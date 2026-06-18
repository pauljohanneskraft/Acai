import Testing
@testable import UMLPython
@testable import UMLCore

@Suite("Python: Type Resolution Tests")
struct PythonTypeResolutionTests {
    let parser = PythonCodeParser()

    private func paramType(_ source: String, method: String, param: String) -> TypeReference? {
        let artifact = parser.parse(source: source, fileName: "test.py")
        let member = artifact.types.flatMap(\.members).first { $0.name == method }
            ?? artifact.freestandingFunctions.first { $0.name == method }
        return member?.parameters.first { $0.internalName == param }?.type
    }

    @Test func optionalUnwrapsToInnerType() {
        let source = """
        from typing import Optional

        def f(value: Optional[int]):
            pass
        """
        let type = paramType(source, method: "f", param: "value")
        #expect(type?.name == "int")
        #expect(type?.isOptional == true)
    }

    @Test func pep604UnionWithNoneIsOptional() {
        let source = """
        def f(value: str | None):
            pass
        """
        let type = paramType(source, method: "f", param: "value")
        #expect(type?.name == "str")
        #expect(type?.isOptional == true)
    }

    @Test func listGenericKeepsElementAsArgument() {
        let source = """
        def f(items: list[User]):
            pass
        """
        let type = paramType(source, method: "f", param: "items")
        #expect(type?.name == "list")
        #expect(type?.genericArguments.map(\.name) == ["User"])
    }

    @Test func dictGenericKeepsBothArguments() {
        let source = """
        from typing import Dict

        def f(mapping: Dict[str, User]):
            pass
        """
        let type = paramType(source, method: "f", param: "mapping")
        #expect(type?.name == "Dict")
        #expect(type?.genericArguments.map(\.name) == ["str", "User"])
    }

    @Test func forwardReferenceStringType() {
        let source = """
        def f(node: "TreeNode"):
            pass
        """
        let type = paramType(source, method: "f", param: "node")
        #expect(type?.name == "TreeNode")
    }

    @Test func qualifiedTypeUsesTrailingName() {
        let source = """
        def f(when: datetime.datetime):
            pass
        """
        let type = paramType(source, method: "f", param: "when")
        #expect(type?.name == "datetime")
    }

    @Test func collectionPropertyBecomesAggregation() {
        let source = """
        class Team:
            def __init__(self):
                self.members: list[Player] = []

        class Player:
            pass
        """
        let artifact = parser.parse(source: source, fileName: "team.py")
            .enriched(configuration: PythonCodeParser().configuration)
        #expect(artifact.relationships.contains {
            $0.kind == .aggregation && $0.targetLabel == "*"
        })
    }
}
