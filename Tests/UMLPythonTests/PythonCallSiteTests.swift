import Testing
@testable import UMLPython
@testable import UMLCore

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
