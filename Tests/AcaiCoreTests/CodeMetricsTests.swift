import Foundation
import Testing
@testable import AcaiCore

/// Tests for static-analysis metrics (ENH-1…4).
@Suite("Core: Code Metrics")
struct CodeMetricsTests {

    private func type(
        _ name: String, kind: TypeKind, accessLevel: AccessLevel = .internal, module: String,
        members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: accessLevel, members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    /// A method whose body writes the stored property `field` (via `self`) — for cohesion tests.
    private func method(_ name: String, writes field: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, assignments: [
            VariableAssignment(targetName: field, op: .assign, value: .init(kind: .expression, text: "0"))
        ])
    }

    /// A method whose body only *reads* the stored property `field` (via `self`) — for cohesion and
    /// feature-envy tests exercising read-capture (issue #111).
    private func method(_ name: String, reads field: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, fieldReads: [FieldAccess(name: field)])
    }

    /// Two modules: `Core` (a protocol + conforming struct) and `App` (a class that
    /// depends on `Shape` through a stored property → cross-module composition).
    private func sampleArtifact() -> CodeArtifact {
        let drawable = type("Drawable", kind: .protocol, accessLevel: .public, module: "Core")
        let shape = type("Shape", kind: .struct, accessLevel: .public, module: "Core",
                         members: [Member(name: "area", kind: .method, accessLevel: .internal)])
        let view = type("View", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "shape", kind: .property, accessLevel: .internal, type: TypeReference(name: "Shape")),
            Member(name: "render", kind: .method, accessLevel: .internal)
        ])
        let rels = [Relationship(kind: .conformance, source: "Shape", target: "Drawable")]
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [drawable, shape, view], relationships: rels,
            globalVariables: [Member(name: "shared", kind: .property, accessLevel: .internal)]
        ).enriched()
    }

    @Test func conceptCounts() {
        let metrics = sampleArtifact().computeMetrics()
        #expect(metrics.counts.totalTypes == 3)
        #expect(metrics.counts.protocols == 1)
        #expect(metrics.counts.byKind["class"] == 1)
        #expect(metrics.counts.byKind["struct"] == 1)
        #expect(metrics.counts.globalVariables == 1)
        #expect(metrics.counts.methods == 2)
        #expect(metrics.counts.properties == 1)
    }

    @Test func moduleCouplingAndAbstractness() {
        let metrics = sampleArtifact().computeMetrics()
        let core = metrics.modules.first { $0.name == "Core" }
        let app = metrics.modules.first { $0.name == "App" }
        // App depends on Core (View → Shape), so Core has afferent and App efferent coupling.
        #expect((core?.afferentCoupling ?? 0) >= 1)
        #expect((app?.efferentCoupling ?? 0) >= 1)
        // Core has a protocol among 2 types → abstractness 0.5; App has none → 0.
        #expect(core?.abstractness == 0.5)
        #expect(app?.abstractness == 0.0)
        // App depends outward and nothing depends on it → fully unstable.
        #expect(app?.instability == 1.0)
    }

    @Test func bodyReferenceCouplingCountsConstruction() {
        // `Factory` (App) only *constructs* `Widget` (Core) in a method body — no signature edge.
        let widget = type("Widget", kind: .struct, accessLevel: .public, module: "Core",
                          members: [Member(name: "make", kind: .method, accessLevel: .internal)])
        let factory = type("Factory", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "build", kind: .method, accessLevel: .internal, referencedTypeNames: ["Widget"])
        ])
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [widget, factory], relationships: []
        ).enriched().computeMetrics()

        let core = metrics.modules.first { $0.name == "Core" }
        let app = metrics.modules.first { $0.name == "App" }
        #expect((core?.afferentCoupling ?? 0) >= 1)   // Widget is now depended upon …
        #expect(core?.instability == 0.0)             // … so Core is no longer 100% unstable.
        #expect((app?.efferentCoupling ?? 0) >= 1)
        // The construction also shows up in the per-type fan metrics.
        #expect((metrics.types.first { $0.name == "Factory" }?.fanOut ?? 0) >= 1)
        #expect((metrics.types.first { $0.name == "Widget" }?.fanIn ?? 0) >= 1)
    }

    @Test func bodyReferenceUsesMemberDeclaringModule() {
        // `Registry` is declared in Core, but the member that constructs `Plugin` (Leaf) lives in the
        // `Wiring` module (an extension elsewhere). Coupling must be attributed to Wiring, not Core.
        let plugin = type("Plugin", kind: .struct, accessLevel: .public, module: "Leaf")
        let registry = TypeDeclaration(
            id: "Registry", name: "Registry", qualifiedName: "Registry", kind: .class,
            accessLevel: .public,
            members: [Member(
                name: "all", kind: .property,
                accessLevel: .internal,
                location: SourceLocation(filePath: "Sources/Wiring/Registry+All.swift", line: 1, column: 1),
                referencedTypeNames: ["Plugin"])],
            location: SourceLocation(filePath: "Sources/Core/Registry.swift", line: 1, column: 1))
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [plugin, registry], relationships: []
        ).enriched().computeMetrics()

        #expect((metrics.modules.first { $0.name == "Leaf" }?.afferentCoupling ?? 0) >= 1)
        // Core must NOT gain efferent coupling from a member declared in Wiring.
        #expect((metrics.modules.first { $0.name == "Core" }?.efferentCoupling ?? 0) == 0)
    }

    @Test func structuralEdgeUsesMemberDeclaringModule() {
        // Mirrors the real `CodeArtifact+ClassDiagram` shape: `Base` (Core) gains a property typed
        // `Widget` via an extension that lives in the *Diagram* module — the same module `Widget` is
        // declared in. The inferred edge originates in Diagram, so it's an intra-Diagram dependency:
        // Core must NOT gain a phantom efferent dependency on Diagram (the cross-module-extension bug).
        let widget = type("Widget", kind: .struct, accessLevel: .public, module: "Diagram")
        let base = TypeDeclaration(
            id: "Base", name: "Base", qualifiedName: "Base", kind: .struct, accessLevel: .public,
            members: [Member(
                name: "widget", kind: .property, accessLevel: .internal,
                type: TypeReference(name: "Widget"),
                location: SourceLocation(filePath: "Sources/Diagram/Base+Widget.swift", line: 1, column: 1))],
            location: SourceLocation(filePath: "Sources/Core/Base.swift", line: 1, column: 1))
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [widget, base], relationships: []
        ).enriched()

        // The inferred edge carries its declaring (extension) file as provenance.
        let edge = artifact.relationships.first { $0.source == "Base" && $0.target == "Widget" }
        #expect(edge?.origin == "Sources/Diagram/Base+Widget.swift")

        // Without provenance this would read as Core → Diagram (efferent 1) and a phantom edge.
        let metrics = artifact.computeMetrics()
        #expect((metrics.modules.first { $0.name == "Core" }?.efferentCoupling ?? 0) == 0)
    }

    @Test func conformanceEdgeFromCrossModuleExtensionUsesExtensionModule() {
        // `Proto` (Diagram) and `Base` (Core); an extension in *Diagram* conforms `Base` to `Proto`
        // (the real AcaiDiff↔AcaiDiagram shape). The conformance originates in Diagram, so it must not
        // make Core depend on Diagram (no phantom edge / module cycle).
        let proto = type("Proto", kind: .protocol, accessLevel: .public, module: "Diagram")
        let base = type("Base", kind: .struct, accessLevel: .public, module: "Core")
        let ext = TypeDeclaration(
            id: "Base", name: "Base", qualifiedName: "Base", kind: .extension, accessLevel: .public,
            inheritedTypes: [TypeReference(name: "Proto")], extensionOf: "Base",
            location: SourceLocation(filePath: "Sources/Diagram/Base+Proto.swift", line: 1, column: 1))
        let resolved = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [proto, base, ext], relationships: []
        ).resolvingExtensions()

        let edge = resolved.relationships.first { $0.kind == .conformance && $0.source == "Base" }
        #expect(edge?.origin == "Sources/Diagram/Base+Proto.swift")

        let metrics = resolved.enriched().computeMetrics()
        #expect((metrics.modules.first { $0.name == "Core" }?.efferentCoupling ?? 0) == 0)
    }

    @Test func typeMetricsCarryDeclaringModule() {
        let metrics = sampleArtifact().computeMetrics()
        #expect(metrics.types.first { $0.name == "Shape" }?.module == "Core")
        #expect(metrics.types.first { $0.name == "View" }?.module == "App")
    }

    // MARK: - Code-smell metrics (issue #101)

    @Test func responseForClassCountsMethodsPlusDistinctCallTargets() {
        // `Service` declares 2 methods and its bodies call 3 distinct targets — one repeated call
        // (`log`) must be de-duplicated, and a same-name call on a different receiver counts separately.
        let service = type("Service", kind: .class, module: "App", members: [
            Member(name: "run", kind: .method, accessLevel: .public, callSites: [
                CallSite(receiver: .type("Logger"), methodName: "log"),
                CallSite(receiver: .type("Logger"), methodName: "log"),
                CallSite(receiver: .type("Store"), methodName: "save")
            ]),
            Member(name: "reset", kind: .method, accessLevel: .public, callSites: [
                CallSite(receiver: .type("Store"), methodName: "log")   // same method, different receiver
            ])
        ])
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [service], relationships: []
        ).enriched().computeMetrics()
        // 2 methods + 3 distinct targets (Logger.log, Store.save, Store.log).
        #expect(metrics.types.first { $0.name == "Service" }?.responseForClass == 5)
    }

    @Test func publicApiSurfaceCountAndRatio() {
        let widget = type("Widget", kind: .struct, accessLevel: .public, module: "App", members: [
            Member(name: "title", kind: .property, accessLevel: .public),
            Member(name: "open", kind: .method, accessLevel: .open),
            Member(name: "cache", kind: .property, accessLevel: .private),
            Member(name: "helper", kind: .method, accessLevel: .internal)
        ])
        // The fold is exposed on the type itself (behaviour on a value).
        #expect(widget.publicMemberCount == 2)
        #expect(widget.publicMemberRatio == 0.5)
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [widget], relationships: []
        ).enriched().computeMetrics()
        let m = metrics.types.first { $0.name == "Widget" }
        #expect(m?.publicMemberCount == 2)          // public property + open method
        #expect(m?.publicMemberRatio == 0.5)        // 2 of 4 members
        // Module surface sums the type surfaces.
        #expect(metrics.modules.first { $0.name == "App" }?.publicMemberCount == 2)
    }

    @Test func mutablePublicStateCountsPubliclySettableStoredProperties() {
        let model = type("Model", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "name", kind: .property, accessLevel: .public),                         // counts
            Member(name: "id", kind: .property, accessLevel: .public, setAccessLevel: .private),  // private(set): out
            Member(name: "computed", kind: .property, accessLevel: .public, isComputed: true),    // computed: out
            Member(name: "secret", kind: .property, accessLevel: .private)                        // non-public: out
        ])
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [model], relationships: []
        ).enriched().computeMetrics()
        #expect(metrics.types.first { $0.name == "Model" }?.mutablePublicState == 1)
    }

    @Test func parameterPressureReportsMaxAndMean() {
        let api = type("API", kind: .class, module: "App", members: [
            Member(name: "noArgs", kind: .method, accessLevel: .public),
            Member(name: "twoArgs", kind: .method, accessLevel: .public, parameters: [
                Parameter(internalName: "a"), Parameter(internalName: "b")
            ]),
            Member(name: "fourArgs", kind: .initializer, accessLevel: .public, parameters: [
                Parameter(internalName: "a"), Parameter(internalName: "b"),
                Parameter(internalName: "c"), Parameter(internalName: "d")
            ]),
            // A property carries no parameter list and must not dilute the mean.
            Member(name: "flag", kind: .property, accessLevel: .public)
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [api], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "API" }
        #expect(m?.maxParameters == 4)
        #expect(m?.meanParameters == 2.0)   // (0 + 2 + 4) / 3 callable members
    }

    @Test func dataClassScoreIsPropertyShareOfMembers() {
        let record = type("Record", kind: .struct, module: "App", members: [
            Member(name: "a", kind: .property, accessLevel: .public),
            Member(name: "b", kind: .property, accessLevel: .public),
            Member(name: "c", kind: .property, accessLevel: .public),
            Member(name: "describe", kind: .method, accessLevel: .public)
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [record], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Record" }
        #expect(m?.dataClassScore == 0.75)   // 3 properties of 4 data-or-behaviour members
    }

    @Test func overrideCountCountsOverriddenMembers() {
        let child = type("Child", kind: .class, module: "App", members: [
            Member(name: "draw", kind: .method, accessLevel: .public, modifiers: [.override]),
            Member(name: "size", kind: .property, accessLevel: .public, modifiers: [.override]),
            Member(name: "extra", kind: .method, accessLevel: .public)
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [child], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Child" }
        #expect(m?.overrideCount == 2)
    }

    @Test func nestingDepthMeasuresNestedTypeTree() {
        let inner = type("Inner", kind: .struct, module: "App")
        let middle = TypeDeclaration(
            id: "Middle", name: "Middle", qualifiedName: "Outer.Middle", kind: .struct,
            accessLevel: .internal, nestedTypes: [inner],
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 1, column: 1))
        let outer = TypeDeclaration(
            id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .struct,
            accessLevel: .internal, nestedTypes: [middle],
            location: SourceLocation(filePath: "Sources/App/Outer.swift", line: 1, column: 1))
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [outer], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Outer" }
        #expect(m?.nestingDepth == 2)   // Outer → Middle → Inner
    }

    @Test func deepAndWideIsDepthTimesChildren() {
        // Base ← Mid ← Leaf gives Mid DIT 1 and NOC 1 → deepAndWide 1.
        let base = type("Base", kind: .class, accessLevel: .public, module: "App")
        let mid = type("Mid", kind: .class, accessLevel: .public, module: "App")
        let leaf = type("Leaf", kind: .class, accessLevel: .public, module: "App")
        let rels = [
            Relationship(kind: .inheritance, source: "Mid", target: "Base"),
            Relationship(kind: .inheritance, source: "Leaf", target: "Mid")
        ]
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [base, mid, leaf], relationships: rels
        ).enriched().computeMetrics().types.first { $0.name == "Mid" }
        #expect(m?.depthOfInheritance == 1)
        #expect(m?.numberOfChildren == 1)
        #expect(m?.deepAndWide == 1)
    }

    @Test func lackOfCohesionCountsDisjointMethodGroups() {
        // Two method pairs that never share a field or call each other → 2 cohesion components.
        // `a`/`b` both write `x`; `c`/`d` both write `y`; the two groups are disconnected.
        let split = type("Split", kind: .class, module: "App", members: [
            Member(name: "x", kind: .property, accessLevel: .private),
            Member(name: "y", kind: .property, accessLevel: .private),
            method("a", writes: "x"), method("b", writes: "x"),
            method("c", writes: "y"), method("d", writes: "y")
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [split], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Split" }
        #expect(m?.lackOfCohesion == 2)
    }

    @Test func cohesiveTypeHasSingleComponent() {
        // Every method touches the shared field `state`, so the type is a single cohesive component.
        let cohesive = type("Cohesive", kind: .class, module: "App", members: [
            Member(name: "state", kind: .property, accessLevel: .private),
            method("start", writes: "state"), method("stop", writes: "state"), method("reset", writes: "state")
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [cohesive], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Cohesive" }
        #expect(m?.lackOfCohesion == 1)
    }

    @Test func featureEnvyFlagsMethodsBiasedTowardAnotherType() {
        // `shuffle` calls `Ledger` twice and itself once → envious. `local` only calls itself → not.
        let ledger = type("Ledger", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "credit", kind: .method, accessLevel: .public),
            Member(name: "debit", kind: .method, accessLevel: .public)
        ])
        let clerk = type("Clerk", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "shuffle", kind: .method, accessLevel: .public, callSites: [
                CallSite(receiver: .type("Ledger"), methodName: "credit"),
                CallSite(receiver: .type("Ledger"), methodName: "debit"),
                CallSite(receiver: .selfDispatch, methodName: "local")   // one self call
            ]),
            Member(name: "local", kind: .method, accessLevel: .public, callSites: [
                CallSite(receiver: .selfDispatch, methodName: "shuffle")   // self only → not envious
            ])
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [ledger, clerk], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Clerk" }
        #expect(m?.featureEnvyMethods == 1)
    }

    @Test func metricsRoundTripThroughCodable() throws {
        let metrics = sampleArtifact().computeMetrics()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoded = try JSONDecoder().decode(CodeMetrics.self, from: encoder.encode(metrics))
        #expect(decoded == metrics)
    }

    @Test func ooMetricsForInheritanceAndDependencies() {
        let metrics = sampleArtifact().computeMetrics()
        let drawable = metrics.types.first { $0.name == "Drawable" }
        let shape = metrics.types.first { $0.name == "Shape" }
        let view = metrics.types.first { $0.name == "View" }
        // Shape conforms to Drawable: Shape DIT 1, Drawable has one child (NOC 1).
        #expect(shape?.depthOfInheritance == 1)
        #expect(drawable?.numberOfChildren == 1)
        // View depends on Shape via its stored property (composition → fanOut ≥ 1).
        #expect(view?.depthOfInheritance == 0)
        #expect((view?.fanOut ?? 0) >= 1)
    }
}

@Suite("Core: Property Count Metric")
struct NumberOfPropertiesMetricTests {
    @Test func numberOfPropertiesCountsOnlyProperties() {
        let bag = TypeDeclaration(
            id: "Bag", name: "Bag", qualifiedName: "Bag", kind: .struct, accessLevel: .internal,
            members: [
                Member(name: "a", kind: .property, accessLevel: .internal),
                Member(name: "b", kind: .property, accessLevel: .internal),
                Member(name: "run", kind: .method, accessLevel: .internal)
            ],
            location: SourceLocation(filePath: "Sources/App/Bag.swift", line: 1, column: 1))
        let m = CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [bag])
            .enriched().computeMetrics().types.first { $0.name == "Bag" }
        #expect(m?.numberOfProperties == 2)
    }
}

// MARK: - Read-aware cohesion / feature-envy (#111) and derived-metric serialization (#112)

extension CodeMetricsTests {

    @Test func methodsSharingAFieldOnlyByReadingAreCohesive() {
        // Neither method writes `state`; they share it purely by *reading* — still one component. Before
        // read-capture (issue #111) this reported 2 (an upper bound); now it is the true LCOM4 of 1.
        let reader = type("Reader", kind: .class, module: "App", members: [
            Member(name: "state", kind: .property, accessLevel: .private),
            method("show", reads: "state"), method("check", reads: "state")
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [reader], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Reader" }
        #expect(m?.lackOfCohesion == 1)
    }

    @Test func sameNamedFreeFunctionCallDoesNotLinkToSiblingMethod() {
        // `a` calls a *free function* named `b` that coincides with sibling method `b`. A `.free` call
        // must not link them the way a self-call would, so the type stays 2 disjoint components — the
        // nil-receiver-is-self imprecision the enum removes (issue #111).
        let loose = type("Loose", kind: .class, module: "App", members: [
            Member(name: "a", kind: .method, accessLevel: .internal, callSites: [
                CallSite(receiver: .free, methodName: "b")]),
            Member(name: "b", kind: .method, accessLevel: .internal)
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [loose], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Loose" }
        #expect(m?.lackOfCohesion == 2)
    }

    @Test func methodReadingItsOwnFieldsIsNotEnvious() {
        // `tally` reads its own field `total` twice and calls `Ledger` once → own(2) ≥ foreign(1), not
        // envious. Without read-capture "own" would be 0 and it would be falsely flagged (issue #111).
        let ledger = type("Ledger", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "credit", kind: .method, accessLevel: .public)
        ])
        let clerk = type("Clerk", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "total", kind: .property, accessLevel: .private),
            Member(name: "tally", kind: .method, accessLevel: .public,
                   callSites: [CallSite(receiver: .type("Ledger"), methodName: "credit")],
                   fieldReads: [FieldAccess(name: "total"), FieldAccess(name: "total")])
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [ledger, clerk], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Clerk" }
        #expect(m?.featureEnvyMethods == 0)
    }

    @Test func freeFunctionCallDoesNotCountAsOwnInterest() {
        // One foreign call + one `.free` call → foreign(1) > own(0) → envious. If the free call were
        // wrongly counted as "own" (the old nil-is-self assumption), own(1) would tie and hide it.
        let ledger = type("Ledger", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "credit", kind: .method, accessLevel: .public)
        ])
        let clerk = type("Clerk", kind: .class, accessLevel: .public, module: "App", members: [
            Member(name: "post", kind: .method, accessLevel: .public, callSites: [
                CallSite(receiver: .type("Ledger"), methodName: "credit"),
                CallSite(receiver: .free, methodName: "log")
            ])
        ])
        let m = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [ledger, clerk], relationships: []
        ).enriched().computeMetrics().types.first { $0.name == "Clerk" }
        #expect(m?.featureEnvyMethods == 1)
    }

    @Test func deepAndWideIsStoredAndSerialized() throws {
        // `B` derives from `A` (DIT 1) and is subclassed by `C` (NOC 1) → deepAndWide 1. Synthesized
        // Codable drops computed properties, so a stored `deepAndWide` must appear in JSON (issue #112).
        let a = type("A", kind: .class, module: "App")
        let b = type("B", kind: .class, module: "App")
        let c = type("C", kind: .class, module: "App")
        let rels = [
            Relationship(kind: .inheritance, source: "B", target: "A"),
            Relationship(kind: .inheritance, source: "C", target: "B")
        ]
        let metrics = CodeArtifact(
            metadata: .init(sourceLanguage: .swift), types: [a, b, c], relationships: rels
        ).enriched().computeMetrics()
        let bMetric = metrics.types.first { $0.name == "B" }
        #expect(bMetric?.depthOfInheritance == 1)
        #expect(bMetric?.numberOfChildren == 1)
        #expect(bMetric?.deepAndWide == 1)

        let json = try JSONEncoder().encode(metrics)
        let root = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let typeEntries = root?["types"] as? [[String: Any]]
        let bJSON = typeEntries?.first { $0["name"] as? String == "B" }
        #expect(bJSON?["deepAndWide"] as? Int == 1)

        let decoded = try JSONDecoder().decode(CodeMetrics.self, from: json)
        #expect(decoded.types.first { $0.name == "B" }?.deepAndWide == 1)
    }
}
