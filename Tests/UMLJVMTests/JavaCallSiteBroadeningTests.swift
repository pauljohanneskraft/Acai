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

    @Test func capturesPropertySelfAndStaticButNotLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        #expect(!sites.contains { $0.methodName == "doThing" })
    }
}
