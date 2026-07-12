import Testing
@testable import UMLSwift
@testable import UMLCore

/// Parser-side recognition of the call-site shapes behind a dead-code false-positive pass: a
/// fully-qualified nested-type receiver, a call inside a stored property's initializer, a closure's
/// implicit `$0` bound to an iterated array's element type, and a local/global deferred to
/// `.ownMethodReturn`/`.propertyChain` when its type isn't provable in this file. See
/// `SwiftCallSiteBroadeningTests` for the original broadened-call-site coverage this extends, and
/// `DeferredCallReceiverResolutionTests` for the corresponding post-merge resolution behavior.
@Suite("Swift: Deferred Call-Site Receivers")
struct SwiftDeferredCallSiteTests {
    let parser = SwiftCodeParser()

    /// A fully-qualified nested-type receiver (`Outer.Content.make()`) resolves the *whole* dotted
    /// prefix, not just the final segment — deferred to the post-merge pass (see
    /// `DeferredCallReceiverResolutionTests.unresolvedTypeNameResolvesQualifiedPathDespiteAmbiguousSimpleName`),
    /// since a bare "Content" can collide with an unrelated nested type of the same simple name
    /// elsewhere in the project.
    @Test func resolvesFullyQualifiedNestedTypeReceiver() {
        let source = """
        struct Outer {
            struct Content { static func make() -> Content { Content() } }
        }
        struct Worker {
            func run() {
                Outer.Content.make()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "make" && $0.receiver == .unresolvedTypeName("Outer.Content") })
    }

    /// A call made only from a *stored* property's initializer expression (`static let light =
    /// make(isDark: false)`) is captured — previously only computed-property accessor bodies were
    /// walked for call sites.
    @Test func capturesCallSiteInStoredPropertyInitializer() {
        let source = """
        struct Palette {
            static func make(isDark: Bool) -> Palette { Palette() }
            static let light = make(isDark: false)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Palette.swift")
        let palette = artifact.types.first { $0.name == "Palette" }
        let light = palette?.members.first { $0.name == "light" }
        #expect(light?.callSites.contains { $0.methodName == "make" && $0.receiver == .selfDispatch } == true)
    }

    /// A closure's implicit `$0` inside a recognised iteration method (`.map { $0.describe() }`)
    /// resolves to the iterated array property's *element* type, not the array itself.
    @Test func resolvesClosureImplicitParameterElementType() {
        let source = """
        struct Item { func describe() {} }
        struct Worker {
            var items: [Item] = []
            func run() {
                items.map { $0.describe() }
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains { $0.methodName == "describe" && $0.receiverType == "Item" })
    }

    /// A local bound from a same-type method call (`let diagram = generatedDiagram(for: id)`) whose
    /// return type isn't declared anywhere in this file defers to `.ownMethodReturn` rather than
    /// dropping the later `diagram.convertToFreeform()` call — the cross-file same-type
    /// method-return-local case (`generatedDiagram(for:)` would be declared in a sibling extension
    /// file in the real codebase; the deferral doesn't require the method to exist in this file).
    @Test func deferMethodReturnLocalWhenReturnTypeIsCrossFile() {
        let source = """
        struct Worker {
            func run(id: String) {
                let diagram = generatedDiagram(for: id)
                diagram.convertToFreeform()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains {
            $0.methodName == "convertToFreeform"
                && $0.receiver == .ownMethodReturn(methodName: "generatedDiagram", remainingHops: [])
        })
    }

    /// A local bound from a `Type.staticMember` access (no call parens, e.g. `ToolRegistry.standard`)
    /// defers to `.propertyChain`, resolved post-merge regardless of whether `Type` is declared in
    /// this file.
    @Test func deferStaticMemberLocalWhenTypeIsCrossFile() {
        let source = """
        struct Worker {
            func run() {
                let registry = ToolRegistry.standard
                registry.registerHandlers()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Worker.swift")
        let worker = artifact.types.first { $0.name == "Worker" }
        let sites = worker?.members.first { $0.name == "run" }?.callSites ?? []
        #expect(sites.contains {
            $0.methodName == "registerHandlers"
                && $0.receiver == .propertyChain(headTypeName: "ToolRegistry", hops: ["standard"])
        })
    }

    /// The top-level (module-scope) analogue of `deferStaticMemberLocalWhenTypeIsCrossFile` — a
    /// `main.swift`-style global bound from `Type.staticMember` still resolves a later top-level call
    /// through it (RC-H's static-member gap: `let registry = ToolRegistry.standard` /
    /// `registry.registerHandlers()`).
    @Test func capturesTopLevelCallOnStaticMemberGlobal() {
        let source = """
        let registry = ToolRegistry.standard
        registry.registerHandlers()
        """
        let artifact = parser.parse(source: source, fileName: "main.swift")
        let topLevel = artifact.freestandingFunctions.first { $0.name == "<top-level>" }
        #expect(topLevel?.callSites.contains {
            $0.methodName == "registerHandlers"
                && $0.receiver == .propertyChain(headTypeName: "ToolRegistry", hops: ["standard"])
        } == true)
    }
}
