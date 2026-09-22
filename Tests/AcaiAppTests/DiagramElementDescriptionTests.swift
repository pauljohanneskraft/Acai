import Foundation
import Testing
import AcaiCore
import AcaiDiagram
import AcaiRender
@testable import AcaiApp

@Suite("Diagram element descriptions")
struct DiagramElementDescriptionTests {

    private func type(_ id: String, kind: TypeKind = .enum) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id, qualifiedName: id, kind: kind,
            accessLevel: .public,
            members: [
                Member(name: "value", kind: .property, accessLevel: .internal, type: TypeReference(name: "Int")),
                Member(name: "run", kind: .method, accessLevel: .internal)
            ],
            enumCases: [EnumCase(name: "one"), EnumCase(name: "two")]
        )
    }

    @Test("A type node reads its kind, then only the member counts it shows")
    func typeNodeCountsVisibleMembers() {
        var config = ClassDiagramConfiguration()
        config.propertyVisibility["Status"] = false
        let node = GeneratedDiagramNode(from: type("Status"), configuration: config)

        let description = DiagramElementDescription(typeNode: node, delta: nil)

        #expect(description.label == "Status")
        #expect(description.details.map(\.key) == [
            "TypeKind.Enum", "DiagramElementDescription.Functions %lld", "DiagramElementDescription.EnumCases %lld"
        ])
    }

    @Test("A change status is read only when the element changed")
    func changeStatusIsReadOnlyWhenChanged() {
        let node = GeneratedDiagramNode(from: type("Status"))

        let added = DiagramElementDescription(typeNode: node, delta: .added)
        let unchanged = DiagramElementDescription(typeNode: node, delta: .unchanged)

        #expect(added.details.last?.key == "DiagramElementDescription.Added")
        #expect(!unchanged.details.map(\.key).contains { $0.hasSuffix("Added") || $0.hasSuffix("Changed") })
    }

    @Test("A call-graph node counts its callers and callees")
    func callGraphNodeCountsCalls() {
        let caller = CallGraph.Node(id: "A.run", typeName: "A", methodName: "run", inScope: true)
        let callee = CallGraph.Node(id: "B.go", typeName: "B", methodName: "go", inScope: false)
        let graph = CallGraph(nodes: [caller, callee], edges: [CallGraph.Edge(from: "A.run", to: "B.go")])

        let description = DiagramElementDescription(callGraphNode: callee, in: graph, delta: .changed)

        #expect(description.label == "B.go")
        #expect(description.details.map(\.key) == [
            "DiagramElementDescription.Method", "DiagramElementDescription.CallsOut %lld",
            "DiagramElementDescription.CalledBy %lld", "DiagramElementDescription.OutsideScope",
            "DiagramElementDescription.Changed"
        ])
        #expect(String(localized: description.details[2]).contains("1"))
        #expect(String(localized: description.details[1]).contains("0"))
    }

    @Test("Every state kind is described, not only boxed states")
    func everyStateKindHasATitle() {
        for kind in StateDiagram.State.Kind.allCases {
            let state = StateDiagram.State(id: kind.rawValue, name: "S", kind: kind)
            let description = DiagramElementDescription(state: state, delta: nil)
            #expect(description.details.first?.key.hasPrefix("StateKind.") == true)
        }
    }

    @Test("A class edge names both ends, its kind and its multiplicities")
    func classEdgeNamesBothEnds() throws {
        let edge = GeneratedDiagramEdge(
            from: Relationship(kind: .composition, source: "Order", target: "Line", sourceLabel: "1", targetLabel: "*"))

        let description = DiagramElementDescription(
            classEdge: edge, sourceName: "Order", targetName: "Line", delta: .removed)

        #expect(description.label.contains("Order"))
        #expect(description.label.contains("Line"))
        #expect(description.details.map(\.key) == [
            "RelationshipKind.Composition", "DiagramElementDescription.SourceMultiplicity %@",
            "DiagramElementDescription.TargetMultiplicity %@", "DiagramElementDescription.Removed"
        ])
        let accessibility = description.edgeAccessibility(identifier: "diagram.edge.Order->Line")
        #expect(accessibility.identifier == "diagram.edge.Order->Line")
        // Every detail belongs in the label: macOS speaks no accessibility value for a drawn edge.
        #expect(accessibility.label.contains("Order"))
        for detail in description.details {
            #expect(accessibility.label.contains(String(localized: detail)))
        }
    }

    @Test("A package node reads its size and coupling")
    func packageNodeReadsCoupling() {
        let node = PackageDiagram.Node(
            id: "Core", name: "Core", typeCount: 12, afferentCoupling: 3, efferentCoupling: 1,
            instability: 0.25, abstractness: 0.5)

        let description = DiagramElementDescription(packageNode: node, delta: nil)

        #expect(description.details.map(\.key) == [
            "DiagramElementDescription.Module", "DiagramElementDescription.Types %lld",
            "DiagramElementDescription.UsedBy %lld", "DiagramElementDescription.Uses %lld",
            "DiagramElementDescription.Instability %@"
        ])
    }
}
