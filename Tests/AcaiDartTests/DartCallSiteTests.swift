import Testing
@testable import AcaiDart
@testable import AcaiCore

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
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    /// A field with no explicit type annotation, initialized by a direct construction
    /// (`var helper = Helper();` — the idiomatic Dart form), must still get its type inferred so a
    /// call through it resolves instead of looking uncalled.
    @Test func unannotatedFieldInfersTypeFromConstructionInitializer() {
        let source = """
        class Helper {
            void process() {}
        }
        class Worker {
            var helper = Helper();

            void run() {
                helper.process();
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let worker = artifact.types.first { $0.name == "Worker" }
        let helperField = worker?.members.first { $0.name == "helper" }
        #expect(helperField?.type?.name == "Helper")

        let run = worker?.members.first { $0.name == "run" }
        #expect(run?.callSites.contains { $0.methodName == "process" && $0.receiverType == "Helper" } == true)
    }

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
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
    }

    /// Resolves the same way `var h = Helper();` already does — including when the method is
    /// declared *after* the caller.
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
            Widget compute() { return Widget(); }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.dart")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "use" && $0.receiverType == "Widget" })
    }

    /// A bare `foo()` is an implicit `this.foo()` (or a top-level function) — captured as
    /// `.selfDispatch`; a constructor call `Foo()` (same grammar shape) is not.
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
    /// aren't false-flagged as dead.
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

    /// A static call on the *enclosing* type must resolve — the enclosing type needs to be
    /// registered before its body is processed.
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
