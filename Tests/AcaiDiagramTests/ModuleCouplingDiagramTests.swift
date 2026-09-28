import Testing
@testable import AcaiDiagram
@testable import AcaiCore

/// The coupling view over `PackageDiagram`: what the labels carry, and that its
/// Stable-Dependencies-Principle marking is the same judgement `CodeMetrics` already makes.
@Suite("Module Coupling Diagram")
struct ModuleCouplingDiagramTests {

    // MARK: - Fixtures

    /// `Core` is stable and partly abstract (deep in the zone of pain at `D=0.67`); `Banking`
    /// sits on the line. Built directly rather than from an artifact so the renderer is exercised
    /// on exact metric values.
    private func twoModuleDiagram() -> PackageDiagram {
        PackageDiagram(
            nodes: [
                PackageDiagram.Node(
                    id: "Banking", name: "Banking", typeCount: 2, afferentCoupling: 0,
                    efferentCoupling: 3, instability: 1, abstractness: 0),
                PackageDiagram.Node(
                    id: "Core", name: "Core", typeCount: 3, afferentCoupling: 2,
                    efferentCoupling: 0, instability: 0, abstractness: 0.33)
            ],
            edges: [PackageDiagram.Edge(from: "Banking", to: "Core", weight: 4)]
        )
    }

    /// `Ledger` depends on `Reporting`, which is *less* stable than it (`I=0.67` against `I=0.50`) —
    /// one SDP breach, with the other three edges pointing the healthy way.
    private func breachingDiagram() -> PackageDiagram {
        PackageDiagram(
            nodes: [
                node("App", instability: 1),
                node("Ledger", instability: 0.5),
                node("Reporting", instability: 0.667),
                node("Money", instability: 0),
                node("Audit", instability: 0)
            ],
            edges: [
                PackageDiagram.Edge(from: "App", to: "Ledger", weight: 1),
                PackageDiagram.Edge(from: "Ledger", to: "Reporting", weight: 2),
                PackageDiagram.Edge(from: "Reporting", to: "Money", weight: 1),
                PackageDiagram.Edge(from: "Reporting", to: "Audit", weight: 1)
            ]
        )
    }

    private func node(_ name: String, instability: Double) -> PackageDiagram.Node {
        PackageDiagram.Node(
            id: name, name: name, typeCount: 1, afferentCoupling: 1,
            efferentCoupling: 1, instability: instability, abstractness: 0.5)
    }

    /// A five-module chain whose `Ledger → Reporting` edge is a real SDP breach once the metrics are
    /// computed: `Reporting` carries two efferent references against one afferent.
    private func breachingArtifact() -> CodeArtifact {
        func type(_ id: String, module: String) -> TypeDeclaration {
            TypeDeclaration(
                id: id, name: id, qualifiedName: id, kind: .class, accessLevel: .public,
                location: .init(filePath: "Sources/\(module)/\(id).swift", line: 1, column: 1))
        }
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                type("AppType", module: "App"), type("LedgerType", module: "Ledger"),
                type("ReportingType", module: "Reporting"), type("MoneyType", module: "Money"),
                type("AuditType", module: "Audit")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "AppType", target: "LedgerType"),
                Relationship(kind: .dependency, source: "LedgerType", target: "ReportingType"),
                Relationship(kind: .dependency, source: "ReportingType", target: "MoneyType"),
                Relationship(kind: .dependency, source: "ReportingType", target: "AuditType")
            ]
        )
    }

    // MARK: - Labels

    @Test("The DOT label carries Ca, Ce, I, A, D and the named zone")
    func dotLabelCarriesTheMetricSet() {
        let dot = ModuleCouplingDOTRenderer().render(twoModuleDiagram())
        #expect(dot.contains("Ca=2  Ce=0"))
        #expect(dot.contains("I=0.00  A=0.33  D=0.67"))
        #expect(dot.contains("zone of pain"))
        #expect(dot.contains("balanced"))
        #expect(dot.contains("3 types"))
    }

    @Test("The Mermaid label carries the same metric set")
    func mermaidLabelCarriesTheMetricSet() {
        let mermaid = ModuleCouplingMermaidRenderer().render(twoModuleDiagram())
        #expect(mermaid.contains("Ca=2 Ce=0"))
        #expect(mermaid.contains("I=0.00 A=0.33 D=0.67"))
        #expect(mermaid.contains("zone of pain"))
        #expect(mermaid.contains("flowchart LR"))
    }

    /// The zone has to survive a monochrome export, so it is text rather than fill alone.
    @Test("A single-type module reads '1 type', not '1 types'")
    func singularTypeCount() {
        let diagram = PackageDiagram(nodes: [node("Solo", instability: 0.5)], edges: [])
        #expect(ModuleCouplingDOTRenderer().render(diagram).contains("\\n1 type\""))
    }

    // MARK: - SDP breaches

    @Test("Only the edge pointing at a less stable module is a breach")
    func breachesAreDerivedFromNodeInstability() {
        let breaches = breachingDiagram().stableDependencyBreaches
        #expect(breaches == [PackageDiagram.Edge(from: "Ledger", to: "Reporting", weight: 2)])
    }

    @Test("A breach is dashed and labelled in DOT, dotted in Mermaid")
    func breachIsMarkedInBothFormats() {
        let dot = ModuleCouplingDOTRenderer().render(breachingDiagram())
        #expect(dot.contains("\"Ledger\" -> \"Reporting\" [penwidth=1.5 label=\"2 (SDP)\" style=dashed]"))
        #expect(dot.contains("\"App\" -> \"Ledger\" [penwidth=1.2 label=\"1\"];"))

        let mermaid = ModuleCouplingMermaidRenderer().render(breachingDiagram())
        #expect(mermaid.contains("Ledger -.->|2 (SDP)| Reporting"))
        #expect(mermaid.contains("App -->|1| Ledger"))
    }

    /// The point of deriving breaches from the diagram rather than re-running the metrics: the two
    /// must not be able to disagree.
    @Test("The diagram's breaches match the metrics' own stableDependencyViolations")
    func breachesAgreeWithComputedMetrics() {
        let artifact = breachingArtifact()
        let diagram = PackageDiagramBuilder().build(from: artifact)

        let fromMetrics = Set(artifact.computeMetrics().modules.flatMap { module in
            module.stableDependencyViolations.map { "\(module.name)→\($0)" }
        })
        let fromDiagram = Set(diagram.stableDependencyBreaches.map { "\($0.from)→\($0.to)" })

        #expect(fromDiagram == fromMetrics)
        #expect(fromMetrics == ["Ledger→Reporting"])
    }

    @Test("Every module's zone matches the zone its own metrics report")
    func nodeZoneMatchesModuleZone() {
        let artifact = breachingArtifact()
        let diagram = PackageDiagramBuilder().build(from: artifact)
        let zonesByModule: [String: MainSequenceZone] = Dictionary(
            uniqueKeysWithValues: artifact.computeMetrics().modules.map { ($0.name, $0.mainSequenceZone) })

        for node in diagram.nodes {
            #expect(node.mainSequenceZone == zonesByModule[node.name])
        }
    }
}
