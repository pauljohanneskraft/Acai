import Testing
@testable import AcaiJS
@testable import AcaiCore

@Suite("JS/TS: Call-Site Broadening")
struct JSCallSiteBroadeningTests {
    let parser = JSCodeParser(isTypeScript: true)

    private func runCallSites() -> [CallSite] {
        let source = """
        class Logger {
            static log() {}
        }
        class Helper {
            process() {}
        }
        class Worker {
            helper: Helper;

            run() {
                this.helper.process();
                this.validate();
                Logger.log();
                const local = new Helper();
                local.doThing();
            }

            validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.ts")
        let worker = artifact.types.first { $0.name == "Worker" }
        return worker?.members.first { $0.name == "run" }?.callSites ?? []
    }

    @Test func capturesPropertySelfStaticAndLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local `const local = new Helper()` now resolves its receiver type (RC4).
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    /// A field with no type annotation, initialized by a direct `new Foo()` construction, must still
    /// get its type inferred — from either JS or untyped TS — so a call through it resolves instead
    /// of looking uncalled.
    @Test func unannotatedFieldInfersTypeFromConstructionInitializer() {
        let source = """
        class Helper {
            process() {}
        }
        class Worker {
            helper = new Helper();
            run() {
                this.helper.process();
            }
        }
        """
        for parser in [JSCodeParser(isTypeScript: true), JSCodeParser(isTypeScript: false)] {
            let artifact = parser.parse(source: source, fileName: "Worker.ts")
            let worker = artifact.types.first { $0.name == "Worker" }
            let helperField = worker?.members.first { $0.name == "helper" }
            #expect(helperField?.type?.name == "Helper")

            let run = worker?.members.first { $0.name == "run" }
            #expect(run?.callSites.contains { $0.methodName == "process" && $0.receiverType == "Helper" } == true)
        }
    }

    /// A TypeScript-typed method parameter is a provable call-site receiver, just like a typed field
    /// (dead-code false positive: RC-G).
    @Test func resolvesCallOnTypedParameter() {
        let source = """
        class Helper {
            process() {}
        }
        class Worker {
            run(helper: Helper) {
                helper.process();
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.ts")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
    }

    /// A local initialized from a same-type method call (`const x = compute()`) resolves its receiver
    /// type from the method's unambiguous TypeScript return-type annotation, the same way a `new
    /// Foo()` construction already does — including when the method is declared *after* the caller
    /// (dead-code false positive: RC-I).
    @Test func resolvesLocalFromSameTypeMethodCallReturnType() {
        let source = """
        class Widget {
            use() {}
        }
        class Worker {
            run() {
                const x = compute();
                x.use();
            }
            compute(): Widget { return new Widget(); }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.ts")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "use" && $0.receiverType == "Widget" })
    }

    /// JS has no implicit `this`, so a bare `foo()` is a free/imported function — captured as `.free`
    /// (previously dropped). Also covers freestanding-function bodies now being walked (RC1).
    @Test func capturesBareFreeFunctionCall() {
        let source = """
        function entry() { helper(); }
        function helper() {}
        """
        let artifact = parser.parse(source: source, fileName: "mod.ts")
        let entry = artifact.freestandingFunctions.first { $0.name == "entry" }
        let sites = entry?.callSites ?? []
        #expect(sites.contains { $0.methodName == "helper" && $0.receiver == .free })
    }

    /// A bare top-level statement (`bootstrap();`) makes a call whose target has nowhere to attach as
    /// a caller — collected separately and given a synthetic reachable member so the callee isn't a
    /// dead-code false positive (RC-H).
    @Test func capturesTopLevelBareCall() {
        let source = """
        function bootstrap() {}
        bootstrap();
        """
        let artifact = parser.parse(source: source, fileName: "index.ts")
        let topLevel = artifact.freestandingFunctions.first { $0.name == "<top-level>" }
        #expect(topLevel?.accessLevel == .public)
        #expect(topLevel?.callSites.contains { $0.methodName == "bootstrap" && $0.receiver == .free } == true)
    }

    /// A call made only from a class field initializer is recorded so its target isn't false-flagged
    /// as dead (RC2).
    @Test func capturesFieldInitializerCall() {
        let source = """
        function makeHandler() {}
        class Worker {
            handler = makeHandler();
        }
        """
        let artifact = parser.parse(source: source, fileName: "mod.ts")
        let worker = artifact.types.first { $0.name == "Worker" }
        let allSites = (worker?.members ?? []).flatMap(\.callSites)
        #expect(allSites.contains { $0.methodName == "makeHandler" })
    }
}
