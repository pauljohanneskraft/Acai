import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("Package Dependency Diagram")
struct PackageDiagramTests {

    // MARK: - Fixtures

    /// Two modules: `ModuleA` (two concrete classes) depends on `ModuleB` (one protocol).
    private func twoModuleArtifact() -> CodeArtifact {
        let typeA = TypeDeclaration(
            id: "A", name: "A", qualifiedName: "A", kind: .class,
            location: .init(filePath: "Sources/ModuleA/A.swift", line: 1, column: 1)
        )
        let typeA2 = TypeDeclaration(
            id: "A2", name: "A2", qualifiedName: "A2", kind: .class,
            location: .init(filePath: "Sources/ModuleA/A2.swift", line: 1, column: 1)
        )
        let typeB = TypeDeclaration(
            id: "B", name: "B", qualifiedName: "B", kind: .protocol,
            location: .init(filePath: "Sources/ModuleB/B.swift", line: 1, column: 1)
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [typeA, typeA2, typeB],
            relationships: [
                Relationship(kind: .conformance, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "A2", target: "B")
            ]
        )
    }

    private func singleModuleArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    location: .init(filePath: "Sources/Only/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    location: .init(filePath: "Sources/Only/B.swift", line: 1, column: 1)
                )
            ],
            relationships: [Relationship(kind: .dependency, source: "A", target: "B")]
        )
    }

    // MARK: - Extractor

    @Test func nodesAreBuildModules() {
        let diagram = twoModuleArtifact().packageDependencyDiagram()
        #expect(Set(diagram.nodes.map(\.name)) == ["ModuleA", "ModuleB"])
    }

    @Test func crossModuleEdgeAggregatesWeight() throws {
        let diagram = twoModuleArtifact().packageDependencyDiagram()
        let edge = try #require(diagram.edges.first { $0.from == "ModuleA" && $0.to == "ModuleB" })
        // Two distinct type crossings (A→B, A2→B) collapse onto one weighted edge.
        #expect(edge.weight == 2)
        #expect(diagram.edges.count == 1)
    }

    @Test func couplingMetricsReflectStability() throws {
        let diagram = twoModuleArtifact().packageDependencyDiagram()
        let moduleA = try #require(diagram.nodes.first { $0.name == "ModuleA" })
        let moduleB = try #require(diagram.nodes.first { $0.name == "ModuleB" })
        // ModuleA only depends outward (unstable); ModuleB is only depended upon (stable & abstract).
        #expect(moduleA.instability == 1.0)
        #expect(moduleB.instability == 0.0)
        #expect(moduleB.abstractness == 1.0)
    }

    @Test func singleModuleHasNoEdges() {
        let diagram = singleModuleArtifact().packageDependencyDiagram()
        #expect(diagram.nodes.count == 1)
        #expect(diagram.edges.isEmpty)
    }

    // MARK: - DOT rendering

    @Test func dotRendersNodesAndWeightedEdge() {
        let diagram = twoModuleArtifact().packageDependencyDiagram()
        let dot = PackageDiagramDOTRenderer().render(diagram)
        #expect(dot.contains("digraph {"))
        #expect(dot.contains("\"ModuleA\""))
        #expect(dot.contains("\"ModuleA\" -> \"ModuleB\""))
        #expect(dot.contains("label=\"2\""))
    }

    // MARK: - Mermaid rendering

    @Test func mermaidRendersFlowchartWithStyleAndWeight() {
        let diagram = twoModuleArtifact().packageDependencyDiagram()
        let mermaid = PackageDiagramMermaidRenderer().render(diagram)
        #expect(mermaid.contains("flowchart LR"))
        #expect(mermaid.contains("ModuleA[\"ModuleA<br/>"))
        #expect(mermaid.contains("ModuleA -->|2| ModuleB"))
        #expect(mermaid.contains("style ModuleA fill:"))
    }

    @Test func mermaidIncludesTitleFrontMatter() {
        let diagram = twoModuleArtifact().packageDependencyDiagram(title: "My Modules")
        let mermaid = PackageDiagramMermaidRenderer().render(diagram)
        #expect(mermaid.contains("title: My Modules"))
        #expect(mermaid.contains("flowchart LR"))
    }

    @Test func dotIncludesTitleAndThickness() {
        let diagram = twoModuleArtifact().packageDependencyDiagram(title: "My Modules")
        let dot = PackageDiagramDOTRenderer().render(diagram)
        #expect(dot.contains("label=\"My Modules\""))
        #expect(dot.contains("labelloc=t"))
        #expect(dot.contains("penwidth="))
    }

    // MARK: - Zone-of-pain color

    @Test func zoneColorBucketsCoverFullRange() {
        func node(_ instability: Double, _ abstractness: Double) -> PackageDependencyDiagram.Node {
            .init(id: "x", name: "x", typeCount: 1, afferentCoupling: 0,
                  efferentCoupling: 0, instability: instability, abstractness: abstractness)
        }
        #expect(node(0.9, 0.1).zoneColorHex == "#c8e6c9")  // D = 0.0 — balanced
        #expect(node(0.6, 0.0).zoneColorHex == "#fff9c4")  // D = 0.4 — drifting
        #expect(node(0.3, 0.0).zoneColorHex == "#ffe0b2")  // D = 0.7 — concerning
        #expect(node(0.0, 0.0).zoneColorHex == "#ffcdd2")  // D = 1.0 — zone of pain
    }
}
