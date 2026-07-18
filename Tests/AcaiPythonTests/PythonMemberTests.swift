import Testing
@testable import AcaiPython
@testable import AcaiCore

@Suite("Python: Member Tests")
struct PythonMemberTests {
    let parser = PythonCodeParser()

    private func type(named name: String, in source: String) -> TypeDeclaration? {
        parser.parse(source: source, fileName: "test.py").types.first { $0.name == name }
    }

    @Test func initializerKindAndSelfDropped() {
        let source = """
        class User:
            def __init__(self, name: str, age: int):
                self.name = name
        """
        let user = type(named: "User", in: source)
        let initializer = user?.members.first { $0.kind == .initializer }
        #expect(initializer?.name == "__init__")
        // `self` is dropped; only name/age remain.
        #expect(initializer?.parameters.map(\.internalName) == ["name", "age"])
        #expect(initializer?.accessLevel == .public)
    }

    @Test func cyclomaticComplexityCountsDecisionPoints() {
        let source = """
        class Analyzer:
            def simple(self):
                return 1

            def branchy(self, xs):
                total = 0
                for x in xs:                 # +1
                    if x > 0:                # +1
                        total += x
                    elif x == 0:             # +1
                        total += 1
                return total
        """
        let analyzer = type(named: "Analyzer", in: source)
        let simple = analyzer?.members.first { $0.name == "simple" }
        let branchy = analyzer?.members.first { $0.name == "branchy" }
        #expect(simple?.cyclomaticComplexity == 1)   // no branches → base complexity
        #expect(branchy?.cyclomaticComplexity == 4)  // 1 + for + if + elif
    }

    @Test func classmethodAndStaticmethodDropReceiver() {
        let source = """
        class Factory:
            @staticmethod
            def create() -> str:
                return "x"

            @classmethod
            def from_config(cls, config: dict) -> str:
                return "y"
        """
        let factory = type(named: "Factory", in: source)
        let create = factory?.members.first { $0.name == "create" }
        #expect(create?.modifiers.contains(.static) == true)
        let fromConfig = factory?.members.first { $0.name == "from_config" }
        // `cls` is dropped.
        #expect(fromConfig?.parameters.map(\.internalName) == ["config"])
    }

    @Test func computedProperty() {
        let source = """
        class Circle:
            def __init__(self, r: float):
                self.r = r

            @property
            def area(self) -> float:
                return 3.14 * self.r
        """
        let circle = type(named: "Circle", in: source)
        let area = circle?.members.first { $0.name == "area" }
        #expect(area?.kind == .property)
        #expect(area?.isComputed == true)
        #expect(area?.type?.name == "float")
    }

    @Test func accessLevelByNamingConvention() {
        let source = """
        class Widget:
            def public_method(self): pass
            def _protected_method(self): pass
            def __private_method(self): pass
            def __dunder__(self): pass
        """
        let widget = type(named: "Widget", in: source)
        func access(_ name: String) -> AccessLevel? {
            widget?.members.first { $0.name == name }?.accessLevel
        }
        #expect(access("public_method") == .public)
        #expect(access("_protected_method") == .protected)
        #expect(access("__private_method") == .private)
        #expect(access("__dunder__") == .public)
    }

    @Test func asyncMethod() {
        let source = """
        class Service:
            async def fetch(self) -> str:
                return "data"
        """
        let service = type(named: "Service", in: source)
        let fetch = service?.members.first { $0.name == "fetch" }
        #expect(fetch?.modifiers.contains(.async) == true)
    }

    @Test func variadicParameters() {
        let source = """
        class Logger:
            def log(self, *args: str, **kwargs: int) -> None:
                pass
        """
        let logger = type(named: "Logger", in: source)
        let log = logger?.members.first { $0.name == "log" }
        #expect(log?.parameters.count == 2)
        #expect(log?.parameters.allSatisfy(\.isVariadic) == true)
        #expect(log?.parameters.map(\.internalName) == ["args", "kwargs"])
    }

    @Test func freestandingFunction() {
        let source = """
        def helper(x: int, y: int) -> int:
            return x + y
        """
        let artifact = parser.parse(source: source, fileName: "helper.py")
        #expect(artifact.freestandingFunctions.map(\.name) == ["helper"])
        #expect(artifact.freestandingFunctions.first?.type?.name == "int")
    }

    @Test func moduleGlobals() {
        let source = """
        VERSION: str = "1.0"
        DEBUG = False
        """
        let artifact = parser.parse(source: source, fileName: "config.py")
        #expect(artifact.globalVariables.map(\.name).sorted() == ["DEBUG", "VERSION"])
        let version = artifact.globalVariables.first { $0.name == "VERSION" }
        #expect(version?.type?.name == "str")
    }
}
