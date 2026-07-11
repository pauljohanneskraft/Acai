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

    @Test func capturesPropertySelfStaticAndLocals() {
        let sites = runCallSites()
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local `var local = Helper()` now resolves its receiver type (RC4).
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    /// A bare `foo()` is an implicit `this.foo()` (or a top-level function) — captured as
    /// `.selfDispatch`; a constructor call `Foo()` (same grammar shape) is not (RC1).
    @Test func capturesBareImplicitSelfCallButNotConstruction() {
        let source = """
        class Helper {
            void make() {}
        }
        class Worker {
            void run() {
                validate();
                Helper();
            }
            void validate() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "validate" && $0.receiver == .selfDispatch })
        #expect(!sites.contains { $0.methodName == "Helper" })
    }

    /// Calls in a field initializer or a constructor initializer list are recorded so their targets
    /// aren't false-flagged as dead (RC2).
    @Test func capturesFieldAndConstructorInitializerListCalls() {
        let source = """
        class Worker {
            final int handler = make();
            final int x;
            Worker() : x = shared();
            static int make() => 0;
            static int shared() => 1;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let members = artifact.types.first { $0.name == "Worker" }?.members ?? []
        let allSites = members.flatMap(\.callSites)
        #expect(allSites.contains { $0.methodName == "make" })
        #expect(allSites.contains { $0.methodName == "shared" })
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
