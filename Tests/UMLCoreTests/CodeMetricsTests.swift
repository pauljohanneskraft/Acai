import Testing
@testable import UMLCore

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
