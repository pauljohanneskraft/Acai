import Testing
@testable import UMLDart
@testable import UMLCore

/// Dart previously captured no call sites at all (the extractor did not conform to
/// `CallSiteResolving`). These cover the now-supported property-receiver, `this.method()`,
/// and `TypeName.method()` forms.
@Suite("Dart: Call-Site Resolution")
struct DartCallSiteTests {
    let parser = DartCodeParser()

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
                var local = Helper();
                local.doThing();
            }

            void validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
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

    /// A static call on the *enclosing* type must resolve. Previously the current class was
    /// appended to `types` only after its body was processed, so the type-name set was missing
    /// it and the call was dropped; the up-front pre-pass fixes this.
    @Test func resolvesStaticCallOnEnclosingType() {
        let source = """
        class Worker {
            static void shared() {}

            void run() {
                Worker.shared();
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "shared" && $0.receiverType == "Worker" })
    }
}
