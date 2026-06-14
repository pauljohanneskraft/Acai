import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin: Call-Site Broadening")
struct KotlinCallSiteBroadeningTests {
    let parser = KotlinCodeParser()

    private func runCallSites() -> [CallSite] {
        let source = """
        class Logger {
            companion object {
                fun log() {}
            }
        }
        class Helper {
            fun process() {}
        }
        class Worker {
            val helper: Helper = Helper()

            fun run() {
                helper.process()
                this.validate()
                Logger.log()
                val local = Helper()
                local.doThing()
            }

            fun validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.kt")
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
