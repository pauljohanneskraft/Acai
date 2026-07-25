import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
import AcaiRender
@testable import AcaiApp

/// "Save as Freeform" for class diagrams (`GeneratedDiagram.convertToFreeform`'s default path):
/// each type becomes a `.type` node and every relationship a matching edge, keyed by type *id* —
/// not name, since two types can share a simple name, and `positions`/`nodePositions` are already
/// id-keyed at every call site (see `ProjectBrowserViewModel+Export.swift`).
@Suite("Class Diagram → Freeform Conversion")
@MainActor
struct ClassFreeformConversionTests {

    private func classDiagram() -> GeneratedDiagram {
        GeneratedDiagram(name: "Classes", content: .classDiagram(.init()), codebaseID: UUID())
    }

    private func type(id: String, name: String) -> TypeDeclaration {
        TypeDeclaration(id: id, name: name, qualifiedName: id, kind: .class, accessLevel: .public)
    }

    private func type(
        id: String, name: String, annotations: [String], sourceLanguage: CodeArtifact.SourceLanguage
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: name, qualifiedName: id, kind: .class, accessLevel: .public,
            annotations: annotations, sourceLanguage: sourceLanguage
        )
    }

    private func type(id: String, name: String, filePath: String) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: name, qualifiedName: id, kind: .class, accessLevel: .public,
            location: .init(filePath: filePath, line: 1, column: 1)
        )
    }

    private func classDiagram(grouping: ClassDiagramConfiguration.Grouping) -> GeneratedDiagram {
        var config = ClassDiagramConfiguration()
        config.grouping = grouping
        return GeneratedDiagram(name: "Classes", content: .classDiagram(config), codebaseID: UUID())
    }

    private func packageNodes(_ freeform: FreeformDiagram) -> [FreeformDiagram.Node] {
        freeform.nodes.filter { if case .package = $0.content { true } else { false } }
    }

    @Test("Same-named types with distinct ids stay separate nodes")
    func sameNameDistinctIdsStaySeparate() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                type(id: "ModuleA.Foo", name: "Foo"),
                type(id: "ModuleB.Foo", name: "Foo")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "ModuleA.Foo", target: "ModuleB.Foo")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 2)
        #expect(freeform.edges.count == 1)
        let edge = try #require(freeform.edges.first)
        #expect(edge.sourceNodeID != edge.targetNodeID)
        let nodeIDs = Set(freeform.nodes.map(\.id))
        #expect(nodeIDs.contains(edge.sourceNodeID))
        #expect(nodeIDs.contains(edge.targetNodeID))
    }

    @Test("Positions carry over keyed by type id, matching real call sites")
    func positionsCarryOverByID() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [type(id: "ModuleA.Foo", name: "Foo")]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact,
            positions: ["ModuleA.Foo": CGPoint(x: 64, y: 128)],
            scale: 1, offset: .zero
        )

        let node = try #require(freeform.nodes.first)
        #expect(node.positionX == 64)
        #expect(node.positionY == 128)
    }

    @Test("Types sharing an id collapse to one node, first declaration wins")
    func sharedIDCollapsesFirstWins() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .python, filePaths: ["a.py", "b.py"]),
            types: [
                type(id: "Dup", name: "Dup"),
                type(id: "Dup", name: "Dup")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "Dup", target: "Dup")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        // The self-referencing relationship is dropped (source == target), same as today, but the
        // node collapse itself must still be first-wins rather than losing identity entirely.
        #expect(freeform.nodes.count == 1)
    }

    @Test("A relationship to an unresolved/external endpoint produces no edge")
    func unresolvedEndpointDropsEdge() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [type(id: "ModuleA.Foo", name: "Foo")],
            relationships: [
                Relationship(kind: .dependency, source: "ModuleA.Foo", target: "SomeExternalType")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 1)
        #expect(freeform.edges.isEmpty)
    }

    @Test("A type with no live/stored position falls back to a staggered stride, not the origin")
    func missingPositionUsesStrideFallback() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                type(id: "ModuleA.Foo", name: "Foo"),
                type(id: "ModuleB.Bar", name: "Bar")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 2)
        for node in freeform.nodes {
            #expect(node.positionX != 0 || node.positionY != 0)
        }
        let positions = Set(freeform.nodes.map { CGPoint(x: $0.positionX, y: $0.positionY) })
        #expect(positions.count == 2)
    }

    @Test("A manually resized node keeps its width/height after conversion")
    func manualResizeSurvivesConversion() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [type(id: "ModuleA.Foo", name: "Foo")]
        )
        var diagram = classDiagram()
        diagram.nodeSizes = ["ModuleA.Foo": .init(width: 340, height: 220)]

        let freeform = diagram.convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        let node = try #require(freeform.nodes.first)
        #expect(node.width == 340)
        #expect(node.height == 220)
    }

    @Test("An annotation-derived stereotype survives conversion")
    func annotationStereotypeSurvivesConversion() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .python, filePaths: ["a.py"]),
            types: [
                type(
                    id: "Foo", name: "Foo", annotations: ["dataclass"],
                    sourceLanguage: .python
                )
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        let node = try #require(freeform.nodes.first)
        #expect(node.content.stereotype == "dataclass")
    }

    @Test("Disabling annotation stereotypes falls back to the kind-based stereotype")
    func disablingAnnotationStereotypesFallsBackToKind() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .python, filePaths: ["a.py"]),
            types: [
                type(
                    id: "Foo", name: "Foo", annotations: ["dataclass"],
                    sourceLanguage: .python
                )
            ]
        )
        var config = ClassDiagramConfiguration()
        config.showAnnotationStereotypes = false
        let diagram = GeneratedDiagram(name: "Classes", content: .classDiagram(config), codebaseID: UUID())

        let freeform = diagram.convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        let node = try #require(freeform.nodes.first)
        // `.class` has no kind-based stereotype (`TypeKind.stereotypeString`), so it falls back to `nil`.
        #expect(node.content.stereotype == nil)
    }

    @Test("Product grouping materializes one package box per module, enclosing its members")
    func productGroupingMaterializesOneBoxPerModule() throws {
        let artifact = CodeArtifact(
            metadata: .init(
                sourceLanguage: .swift, filePaths: ["Sources/AcaiCore/Foo.swift", "Sources/AcaiApp/Bar.swift"]
            ),
            types: [
                type(id: "Foo", name: "Foo", filePath: "Sources/AcaiCore/Foo.swift"),
                type(id: "Bar", name: "Bar", filePath: "Sources/AcaiApp/Bar.swift")
            ]
        )

        let freeform = classDiagram(grouping: .product).convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        let boxes = packageNodes(freeform)
        #expect(boxes.count == 2)
        #expect(Set(boxes.map(\.name)) == ["AcaiCore", "AcaiApp"])

        let typeNodes = freeform.nodes.filter { if case .type = $0.content { true } else { false } }
        #expect(typeNodes.count == 2)
        for typeNode in typeNodes {
            let enclosing = try #require(boxes.first { box in
                let rect = CGRect(
                    x: box.positionX - (box.width ?? 0) / 2, y: box.positionY - (box.height ?? 0) / 2,
                    width: box.width ?? 0, height: box.height ?? 0
                )
                return rect.contains(CGPoint(x: typeNode.positionX, y: typeNode.positionY))
            })
            #expect(enclosing.drawOrder < typeNode.drawOrder)
        }
    }

    @Test("Directory grouping nests a box per path-prefix depth")
    func directoryGroupingNestsByPathPrefix() throws {
        let artifact = CodeArtifact(
            metadata: .init(
                sourceLanguage: .swift, filePaths: ["Sources/AcaiCore/Sub/Foo.swift", "Sources/AcaiCore/Bar.swift"]
            ),
            types: [
                type(id: "Foo", name: "Foo", filePath: "Sources/AcaiCore/Sub/Foo.swift"),
                type(id: "Bar", name: "Bar", filePath: "Sources/AcaiCore/Bar.swift")
            ]
        )

        let freeform = classDiagram(grouping: .directory).convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        let boxNames = Set(packageNodes(freeform).map(\.name))
        #expect(boxNames == ["Sources", "AcaiCore", "Sub"])
    }

    @Test("No grouping produces no package boxes, even when file paths are known")
    func noGroupingProducesNoBoxes() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/AcaiCore/Foo.swift"]),
            types: [type(id: "Foo", name: "Foo", filePath: "Sources/AcaiCore/Foo.swift")]
        )

        let freeform = classDiagram(grouping: .none).convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(packageNodes(freeform).isEmpty)
    }
}
