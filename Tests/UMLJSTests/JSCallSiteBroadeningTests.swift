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

    @Test func capturesPropertySelfAndStaticButNotLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        #expect(!sites.contains { $0.methodName == "doThing" })
    }
}
