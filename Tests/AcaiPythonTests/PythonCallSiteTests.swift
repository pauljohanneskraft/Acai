import Testing
@testable import AcaiPython
@testable import AcaiCore

@Suite("Python: Call Site Tests")
struct PythonCallSiteTests {
    let parser = PythonCodeParser()

    private func callSites(_ source: String, method: String) -> [CallSite] {
        parser.parse(source: source, fileName: "test.py")
            .types.flatMap(\.members).first { $0.name == method }?.callSites ?? []
    }

    @Test func selfMethodCall() {
        let source = """
        class Service:
            def run(self):
                self.helper()

            def helper(self):
                pass
        """
        let sites = callSites(source, method: "run")
        #expect(sites.contains { $0.methodName == "helper" && $0.receiverType == nil })
    }

    @Test func callOnTypedProperty() {
        let source = """
        class Engine:
            def start(self):
                pass

        class Car:
            def __init__(self):
                self.engine: Engine = Engine()

            def drive(self):
                self.engine.start()
        """
        let sites = callSites(source, method: "drive")
        #expect(sites.contains { $0.methodName == "start" && $0.receiverType == "Engine" })
    }

    @Test func staticCallOnKnownType() {
        let source = """
        class Config:
            def load(self):
                pass

        class App:
            def boot(self):
                Config.load()
        """
        let sites = callSites(source, method: "boot")
        #expect(sites.contains { $0.methodName == "load" && $0.receiverType == "Config" })
    }

    /// A type-annotated parameter is a provable call-site receiver, just like a typed property
    /// (dead-code false positive: RC-G).
    @Test func callOnTypedParameter() {
        let source = """
        class Engine:
            def start(self):
                pass

        class Car:
            def drive(self, engine: Engine):
                engine.start()
        """
        let sites = callSites(source, method: "drive")
        #expect(sites.contains { $0.methodName == "start" && $0.receiverType == "Engine" })
    }

    /// A local initialized from a same-type method call (`x = compute()`) resolves its receiver type
    /// from the method's unambiguous `-> Type` annotation, the same way `x = Engine()` already does —
    /// including when the method is declared *after* the caller (dead-code false positive: RC-I).
    @Test func resolvesLocalFromSameTypeMethodCallReturnType() {
        let source = """
        class Widget:
            def use(self):
                pass

        class Worker:
            def run(self):
                x = self.compute()
                x.use()

            def compute(self) -> Widget:
                return Widget()
        """
        let sites = callSites(source, method: "run")
        #expect(sites.contains { $0.methodName == "use" && $0.receiverType == "Widget" })
    }

    /// A call made only from a class-body field initializer is recorded so its target isn't
    /// false-flagged as dead (RC2).
    @Test func capturesClassBodyFieldInitializerCall() {
        let source = """
        def make_handler():
            pass

        class Worker:
            handler = make_handler()
        """
        let sites = callSites(source, method: "handler")
        #expect(sites.contains { $0.methodName == "make_handler" && $0.receiver == .free })
    }

    /// A local whose type is provable from construction (`x = Foo()`) or an annotation (`x: Foo = …`)
    /// resolves the receiver of a later `x.method()` (RC4).
    @Test func resolvesLocalFromConstructionAndAnnotation() {
        let source = """
        class Engine:
            def start(self):
                pass

        class Car:
            def drive(self):
                a = Engine()
                a.start()
                b: Engine = make()
                b.start()
        """
        let sites = callSites(source, method: "drive")
        #expect(sites.filter { $0.methodName == "start" && $0.receiverType == "Engine" }.count == 2)
    }

    /// The idiomatic `if __name__ == "__main__": main()` entry point makes a call whose target has
    /// nowhere to attach as a caller — collected separately and given a synthetic reachable member so
    /// `main` isn't a dead-code false positive (RC-H).
    @Test func capturesTopLevelMainGuardCall() {
        let source = """
        def main():
            pass

        if __name__ == "__main__":
            main()
        """
        let artifact = parser.parse(source: source, fileName: "script.py")
        let topLevel = artifact.freestandingFunctions.first { $0.name == "<top-level>" }
        #expect(topLevel?.accessLevel == .public)
        #expect(topLevel?.callSites.contains { $0.methodName == "main" } == true)
    }

    @Test func callOnUnknownReceiverIsDropped() {
        let source = """
        class App:
            def boot(self):
                unknown_local.do_something()
        """
        let sites = callSites(source, method: "boot")
        #expect(sites.isEmpty)
    }
}
