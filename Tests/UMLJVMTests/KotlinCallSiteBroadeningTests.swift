import Testing
@testable import UMLJVM
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

    @Test func capturesPropertySelfStaticAndLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local `val local = Helper()` now resolves its receiver type (RC4).
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    /// A bare `foo()` (an implicit-receiver call to a sibling method or top-level function) is
    /// captured as `.selfDispatch`; a constructor call `Foo()` (same grammar shape) is not (RC1).
    @Test func capturesBareImplicitSelfCallButNotConstruction() {
        let source = """
        class Helper {
            fun make() {}
        }
        class Worker {
            fun run() {
                helper()
                Helper()
            }
            fun helper() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.kt")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "helper" && $0.receiver == .selfDispatch })
        #expect(!sites.contains { $0.methodName == "Helper" })
    }

    /// Calls made only from a property initializer, an `init { }` block, or a custom accessor are
    /// recorded so their targets aren't false-flagged as dead (RC2).
    @Test func capturesInitializerInitBlockAndAccessorCalls() {
        let source = """
        class Worker {
            val handler = makeHandler()
            init { wire() }
            val label: String get() = format()
            fun makeHandler(): Int = 0
            fun wire() {}
            fun format(): String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.kt")
        let worker = artifact.types.first { $0.name == "Worker" }
        let allSites = (worker?.members ?? []).flatMap(\.callSites)
        #expect(allSites.contains { $0.methodName == "makeHandler" })
        #expect(allSites.contains { $0.methodName == "wire" })
        #expect(allSites.contains { $0.methodName == "format" })
    }
}
