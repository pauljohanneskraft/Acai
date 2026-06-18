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
