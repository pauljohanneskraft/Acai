import Testing
@testable import UMLJVM
@testable import UMLCore

@Suite("Java: Call-Site Broadening")
struct JavaCallSiteBroadeningTests {
    let parser = JavaCodeParser()

    private func runCallSites() -> [CallSite] {
        let source = """
        class Logger {
            static void log() {}
        }
        class Helper {
            void process() {}
        }
        class Worker {
            Helper helper;

            void run() {
                helper.process();
                this.validate();
                Logger.log();
                Helper local = new Helper();
                local.doThing();
            }

            void validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.java")
        let worker = artifact.types.first { $0.name == "Worker" }
        return worker?.members.first { $0.name == "run" }?.callSites ?? []
    }

    @Test func capturesPropertySelfStaticAndLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local `Helper local = new Helper()` now resolves its receiver type (RC4).
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    /// A bare `foo()` (implicit `this.foo()` or a static import) is captured as `.selfDispatch`
    /// so the enclosing type's sibling methods aren't false-flagged as dead (RC1).
    @Test func capturesBareImplicitSelfCall() {
        let source = """
        class Worker {
            void run() { helper(); }
            void helper() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.java")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "helper" && $0.receiver == .selfDispatch })
    }

    /// A typed method parameter is a provable call-site receiver, just like a stored property
    /// (dead-code false positive: RC-G).
    @Test func resolvesCallOnTypedParameter() {
        let source = """
        class Helper {
            void process() {}
        }
        class Worker {
            void run(Helper helper) {
                helper.process();
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.java")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
    }

    /// A local initialized from a same-type method call (`var x = compute();`) resolves its receiver
    /// type from the method's unambiguous return type, the same way a `new Foo()` construction
    /// already does — including when the method is declared *after* the caller (dead-code false
    /// positive: RC-I).
    @Test func resolvesLocalFromSameTypeMethodCallReturnType() {
        let source = """
        class Widget {
            void use() {}
        }
        class Worker {
            void run() {
                var x = compute();
                x.use();
            }
            Widget compute() { return new Widget(); }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.java")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "use" && $0.receiverType == "Widget" })
    }

    /// Calls made only from a field initializer, an instance `{ }` block, or a `static { }` block are
    /// recorded so their targets aren't false-flagged as dead (RC2).
    @Test func capturesFieldInitializerAndInitBlockCalls() {
        let source = """
        class Worker {
            int handler = makeHandler();
            { wire(); }
            static { boot(); }
            int makeHandler() { return 0; }
            void wire() {}
            static void boot() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.java")
        let worker = artifact.types.first { $0.name == "Worker" }
        let allSites = (worker?.members ?? []).flatMap(\.callSites)
        #expect(allSites.contains { $0.methodName == "makeHandler" })
        #expect(allSites.contains { $0.methodName == "wire" })
        #expect(allSites.contains { $0.methodName == "boot" })
    }
}
