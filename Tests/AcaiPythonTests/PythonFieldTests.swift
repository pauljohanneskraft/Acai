import Testing
@testable import AcaiPython
@testable import AcaiCore

@Suite("Python: Field Tests")
struct PythonFieldTests {
    let parser = PythonCodeParser()

    private func type(named name: String, in source: String) -> TypeDeclaration? {
        parser.parse(source: source, fileName: "test.py").types.first { $0.name == name }
    }

    @Test func synthesizesInstanceAttributesFromSelf() {
        let source = """
        class User:
            def __init__(self, name, age):
                self.name = name
                self.age = age
        """
        let user = type(named: "User", in: source)
        let props = user?.members.filter { $0.kind == .property }.map(\.name)
        #expect(props == ["name", "age"])
    }

    @Test func annotatedSelfAttributeCarriesType() {
        let source = """
        class Bag:
            def __init__(self):
                self._items: list[str] = []
        """
        let bag = type(named: "Bag", in: source)
        let items = bag?.members.first { $0.name == "_items" }
        #expect(items?.kind == .property)
        #expect(items?.accessLevel == .protected)
        #expect(items?.type?.name == "list")
    }

    /// `self.x = Foo()` with no annotation — the far more common idiom than `self.x: Foo = Foo()` —
    /// must still infer `Foo` as the attribute's type, so a call through it (`self.cache.process()`)
    /// resolves instead of looking like dead code.
    @Test func unannotatedSelfAttributeInfersTypeFromConstruction() {
        let source = """
        class Cache:
            def process(self):
                pass

        class Worker:
            def __init__(self):
                self.cache = Cache()

            def run(self):
                self.cache.process()
        """
        let worker = type(named: "Worker", in: source)
        let cache = worker?.members.first { $0.name == "cache" }
        #expect(cache?.type?.name == "Cache")

        let run = worker?.members.first { $0.name == "run" }
        #expect(run?.callSites.contains { $0.methodName == "process" && $0.receiverType == "Cache" } == true)
    }

    @Test func classBodyAnnotatedFields() {
        let source = """
        from dataclasses import dataclass

        @dataclass
        class Point:
            x: int
            y: int = 0
        """
        let point = type(named: "Point", in: source)
        let props = point?.members.filter { $0.kind == .property }
        #expect(props?.map(\.name) == ["x", "y"])
        #expect(props?.allSatisfy { $0.type?.name == "int" } == true)
    }

    @Test func selfAttributesDedupedAcrossMethods() {
        let source = """
        class Counter:
            def __init__(self):
                self.count = 0

            def reset(self):
                self.count = 0
                self.last = None
        """
        let counter = type(named: "Counter", in: source)
        let props = counter?.members.filter { $0.kind == .property }.map(\.name)
        // `count` appears in two methods but is emitted once; `last` is also captured.
        #expect(props == ["count", "last"])
    }

    @Test func classBodyFieldWinsOverSelfAssignment() {
        let source = """
        class Config:
            timeout: int = 30

            def __init__(self):
                self.timeout = 60
        """
        let config = type(named: "Config", in: source)
        let timeouts = config?.members.filter { $0.name == "timeout" }
        // Declared once: the class-body annotated field, not a duplicate from self.timeout.
        #expect(timeouts?.count == 1)
        #expect(timeouts?.first?.type?.name == "int")
    }

    @Test func enumCasesAreNotProperties() {
        let source = """
        from enum import Enum

        class Status(Enum):
            ACTIVE = 1
            INACTIVE = 2

            def is_active(self) -> bool:
                return self == Status.ACTIVE
        """
        let status = type(named: "Status", in: source)
        #expect(status?.enumCases.map(\.name) == ["ACTIVE", "INACTIVE"])
        // The cases are not also emitted as properties; the method still is a member.
        #expect(status?.members.filter { $0.kind == .property }.isEmpty == true)
        #expect(status?.members.contains { $0.name == "is_active" } == true)
    }
}
