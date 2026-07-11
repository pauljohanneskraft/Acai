import Testing
@testable import UMLJS
@testable import UMLCore

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
