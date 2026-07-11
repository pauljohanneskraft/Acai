import Testing
@testable import UMLSwift
@testable import UMLCore

/// Covers the broadened (but still statically-certain) call-site forms: `self.method()`
/// self-calls, `TypeName.method()` static calls, and a call on a local whose type is provable from
/// its construction initializer — alongside the existing property-receiver form.
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

    @Test func capturesPropertySelfStaticAndTypedLocalReceivers() {
        let sites = runCallSites()
        // process (property → Helper), validate (self → nil), log (static → Logger),
        // doThing (local `Helper()` → Helper).
        #expect(sites.count == 4)
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
        #expect(sites.contains { $0.methodName == "validate" && $0.receiverType == nil })
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
        // A local whose type is provable from its construction resolves to that type.
        #expect(sites.contains { $0.methodName == "doThing" && $0.receiverType == "Helper" })
    }

    private func callSites(in source: String, method: String, ofType type: String = "Worker") -> [CallSite] {
        let artifact = parser.parse(source: source, fileName: "\(type).swift")
        let decl = artifact.types.first { $0.name == type }
        return decl?.members.first { $0.name == method }?.callSites ?? []
    }

    /// A bare `foo()` — the idiomatic implicit-`self` call — is recorded as a `.selfDispatch` site so
    /// the call graph can resolve it against the caller's own methods (issue: dead-code false positives).
    @Test func capturesBareImplicitSelfCall() {
        let sites = callSites(in: """
        class Worker {
            func run() { parse() }
            func parse() {}
        }
        """, method: "run")
        #expect(sites.count == 1)
        #expect(sites.contains { $0.methodName == "parse" && $0.receiverType == nil })
    }

    /// `Foo()` / `UUID()` are constructions, not calls: a same-file declared type or any capitalised
    /// identifier is treated as a type name and dropped, so they never masquerade as method calls.
    @Test func doesNotCaptureConstruction() {
        let sites = callSites(in: """
        struct Widget {}
        class Worker {
            func run() {
                let w = Widget()
                _ = UUID()
                _ = w
            }
        }
        """, method: "run")
        #expect(sites.isEmpty)
    }

    /// Generic-specialised (`render<Int>()`), trailing-closure (`build { }`), and optional-chained
    /// (`maybe?()`) bare calls all reduce to their callee name and are captured as `.selfDispatch`.
    @Test func capturesGenericTrailingClosureAndOptionalForms() {
        let sites = callSites(in: """
        class Worker {
            func run() {
                render()
                build { }
                maybe?()
            }
            func render<T>() {}
            func build(_ f: () -> Void) {}
            func maybe() {}
        }
        """, method: "run")
        #expect(sites.map(\.methodName).sorted() == ["build", "maybe", "render"])
        #expect(sites.allSatisfy { $0.receiverType == nil })
    }

    /// A call through a stored closure property (`handler()`) isn't a resolvable method target, so it
    /// is dropped rather than mis-recorded as a self method call.
    @Test func dropsStoredClosurePropertyCall() {
        let sites = callSites(in: """
        class Worker {
            let handler: () -> Void
            func run() { handler() }
        }
        """, method: "run")
        #expect(sites.isEmpty)
    }

    /// A static call on a sibling type declared *after* the caller must still resolve, now that
    /// type names are collected in one pre-pass rather than incrementally as types are visited.
    @Test func resolvesStaticCallOnForwardDeclaredSibling() {
        let source = """
        class Worker {
            func run() {
                Logger.log()
            }
        }
        class Logger { static func log() {} }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "log" && $0.receiverType == "Logger" })
    }
}
