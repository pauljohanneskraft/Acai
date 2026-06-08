import Testing
@testable import UMLCore

/// Tests for static-analysis metrics (ENH-1…4).
@Suite("Core: Code Metrics")
struct CodeMetricsTests {

    private func type(
        _ name: String, kind: TypeKind, module: String,
        members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    /// Two modules: `Core` (a protocol + conforming struct) and `App` (a class that
    /// depends on `Shape` through a stored property → cross-module composition).
    private func sampleArtifact() -> CodeArtifact {
        let drawable = type("Drawable", kind: .protocol, module: "Core")
        let shape = type("Shape", kind: .struct, module: "Core",
                         members: [Member(name: "area", kind: .method)])
        let view = type("View", kind: .class, module: "App", members: [
            Member(name: "shape", kind: .property, type: TypeReference(name: "Shape")),
            Member(name: "render", kind: .method)
        ])
        let rels = [Relationship(kind: .conformance, source: "Shape", target: "Drawable")]
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [drawable, shape, view], relationships: rels,
            globalVariables: [Member(name: "shared", kind: .property)]
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
