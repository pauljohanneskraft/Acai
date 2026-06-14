import Testing
@testable import UMLSwift
@testable import UMLCore

/// Covers the broadened (but still statically-certain) call-site forms: `self.method()`
/// self-calls and `TypeName.method()` static calls, alongside the existing property-receiver
/// form — while confirming non-resolvable receivers (locals) are still dropped.
@Suite("Swift: Call-Site Broadening")
struct SwiftCallSiteBroadeningTests {
    let parser = SwiftCodeParser()

    private func runCallSites() -> [CallSite] {
        let source = """
        class Logger { static func log() {} }
        class Helper { func process() {} }
        class Worker {
            var helper: Helper
            func run() {
                helper.process()
                self.validate()
                Logger.log()
                let local = Helper()
                local.doThing()
            }
            func validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        return worker?.members.first { $0.name == "run" }?.callSites ?? []
    }

    @Test func capturesPropertySelfAndStaticButNotLocals() {
        let sites = runCallSites()
        // process (property → Helper), validate (self → nil), log (static → Logger).
        #expect(sites.count == 3)
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local variable's call is not provably resolvable and must be dropped.
        #expect(!sites.contains { $0.methodName == "doThing" })
    }
}
