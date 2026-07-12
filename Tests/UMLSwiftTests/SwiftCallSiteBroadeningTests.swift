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

    /// `Self.foo()` is a static call on the enclosing type, kept distinct from `self.foo()`/bare
    /// `foo()` (`.selfDispatch`): resolving to `.type(enclosingTypeName)` lets it match a
    /// `private static func` "namespace helper" (a common dead-code false positive) without
    /// conflating static and instance dispatch.
    @Test func resolvesSelfCapitalizedAsStaticCallOnEnclosingType() {
        let sites = callSites(in: """
        class Worker {
            func run() { Self.helper() }
            private static func helper() {}
        }
        """, method: "run")
        #expect(sites.count == 1)
        #expect(sites.contains { $0.methodName == "helper" && $0.receiverType == "Worker" })
    }

    /// `self.foo()`/bare `foo()` must still resolve as `.selfDispatch`, not `.type(...)` — regression
    /// guard so the `Self.` fix doesn't blur the self/Self distinction the other direction.
    @Test func lowercaseSelfAndBareCallStayAsSelfDispatch() {
        let sites = callSites(in: """
        class Worker {
            func run() {
                self.validate()
                validate()
            }
            func validate() {}
        }
        """, method: "run")
        #expect(sites.count == 2)
        #expect(sites.allSatisfy { $0.methodName == "validate" && $0.receiverType == nil })
    }

    /// A typed function parameter is a provable call-site receiver, just like a stored property —
    /// `param.method()` inside the body must resolve (dead-code false positive: RC-G).
    @Test func resolvesCallOnTypedParameter() {
        let sites = callSites(in: """
        class Helper { func process() {} }
        class Worker {
            func run(helper: Helper) {
                helper.process()
            }
        }
        """, method: "run")
        #expect(sites.count == 1)
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Helper" })
    }

    /// A parameter shadows a same-named stored property, mirroring how a local already shadows one.
    @Test func parameterShadowsSameNamedProperty() {
        let sites = callSites(in: """
        class Helper { func process() {} }
        class Other { func process() {} }
        class Worker {
            var helper: Helper
            func run(helper: Other) {
                helper.process()
            }
        }
        """, method: "run")
        #expect(sites.contains { $0.methodName == "process" && $0.receiverType == "Other" })
    }

    /// A local initialized from a same-type method call (`let x = compute()` / `let x =
    /// self.compute()`) resolves its receiver type from the method's unambiguous return type, the
    /// same way a direct construction already does (dead-code false positive: RC-I).
    @Test func resolvesLocalFromSameTypeMethodCallReturnType() {
        let sites = callSites(in: """
        class Widget { func use() {} }
        class Worker {
            func run() {
                let x = compute()
                x.use()
                let y = self.computeToo()
                y.use()
            }
            func compute() -> Widget { Widget() }
            func computeToo() -> Widget { Widget() }
        }
        """, method: "run")
        #expect(sites.filter { $0.methodName == "use" && $0.receiverType == "Widget" }.count == 2)
    }

    /// A bare top-level statement (a `main.swift`-style script) makes a call whose target has nowhere
    /// to attach as a caller — collected separately and given a synthetic reachable member so the
    /// callee isn't a dead-code false positive (RC-H).
    @Test func capturesTopLevelBareCall() {
        let source = """
        func boot() {}
        boot()
        """
        let artifact = parser.parse(source: source, fileName: "main.swift")
        let topLevel = artifact.freestandingFunctions.first { $0.name == "<top-level>" }
        #expect(topLevel?.accessLevel == .public)
        #expect(topLevel?.callSites.contains { $0.methodName == "boot" && $0.receiver == .selfDispatch } == true)
    }

    /// A top-level call resolves on a global whose type is provable (an explicit annotation or a
    /// direct construction), declared earlier in the file — the top-level analogue of a stored
    /// property receiver (RC-H).
    @Test func capturesTopLevelCallOnTypedGlobal() {
        let source = """
        class Registry { func registerHandlers() {} }
        let registry = Registry()
        registry.registerHandlers()
        """
        let artifact = parser.parse(source: source, fileName: "main.swift")
        let topLevel = artifact.freestandingFunctions.first { $0.name == "<top-level>" }
        #expect(topLevel?.callSites.contains {
            $0.methodName == "registerHandlers" && $0.receiverType == "Registry"
        } == true)
    }

    /// A protocol extension's default implementation calling through a requirement property
    /// (`history.undo()`, where `history` is declared on the protocol, not the extension) must
    /// resolve — the extension's own member list never carries the protocol's requirement
    /// properties, so this was previously dropped (dead-code false positive: WS7).
    @Test func resolvesCallThroughProtocolRequirementPropertyInExtension() {
        let source = """
        class History { func undo() {} }
        protocol Hosting: AnyObject {
            var history: History { get }
        }
        extension Hosting {
            func undo() {
                history.undo()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Hosting.swift")
        let ext = artifact.types.first { $0.name == "Hosting" && $0.kind == .extension }
        let sites = ext?.members.first { $0.name == "undo" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "undo" && $0.receiverType == "History" })
    }

    /// The method whose return type seeds a local can be declared *after* the caller in source order
    /// — the return-type map is pre-passed the same way `knownTypeNames` already is.
    @Test func resolvesLocalFromForwardDeclaredMethodReturnType() {
        let sites = callSites(in: """
        class Widget { func use() {} }
        class Worker {
            func run() {
                let x = compute()
                x.use()
            }
            func compute() -> Widget { Widget() }
        }
        """, method: "run")
        #expect(sites.contains { $0.methodName == "use" && $0.receiverType == "Widget" })
    }

    /// An overloaded method name with *differing* return types is ambiguous, so a local initialized
    /// from it must not be guessed — the call through it stays unresolved (dropped) rather than
    /// silently attributed to the wrong type.
    @Test func doesNotResolveLocalFromAmbiguousOverloadedReturnType() {
        let sites = callSites(in: """
        class Widget { func use() {} }
        class Gadget { func use() {} }
        class Worker {
            func run() {
                let x = compute()
                x.use()
            }
            func compute() -> Widget { Widget() }
            func compute(flag: Bool) -> Gadget { Gadget() }
        }
        """, method: "run")
        // The bare `compute()` call itself still resolves as self-dispatch; only the *local's* type
        // (and hence the `x.use()` call through it) is left unresolved.
        #expect(sites.contains { $0.methodName == "compute" && $0.receiver == .selfDispatch })
        #expect(!sites.contains { $0.methodName == "use" })
    }

    /// A method whose return type isn't a plain named type (a tuple, here) is excluded from the
    /// return-type map entirely (`IdentifierTypeSyntax` casting fails for `TupleTypeSyntax`), so the
    /// local it initializes gets no inferred type — and tuple-element access (`.0`) isn't a
    /// recognised receiver shape regardless. Both guards mean this never resolves, rather than being
    /// silently misattributed to one of the tuple's element types.
    @Test func doesNotResolveLocalFromTupleReturningMethod() {
        let sites = callSites(in: """
        class Widget { func hello() {} }
        class Worker {
            func run() {
                let myTuple = compute()
                myTuple.0.hello()
            }
            func compute() -> (Widget, Int) { (Widget(), 1) }
        }
        """, method: "run")
        #expect(sites.contains { $0.methodName == "compute" && $0.receiver == .selfDispatch })
        #expect(!sites.contains { $0.methodName == "hello" })
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
