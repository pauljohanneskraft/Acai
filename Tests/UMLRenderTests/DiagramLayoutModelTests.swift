import Testing
import CoreGraphics
@testable import UMLRender
@testable import UMLCore

@Suite("Diagram Layout Model Tests")
struct DiagramLayoutModelTests {

    private func sampleArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/A/Animal.swift", "Sources/A/Dog.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "name", kind: .property,
                        accessLevel: .internal, type: TypeReference(name: "String"))],
                    location: SourceLocation(filePath: "Sources/A/Animal.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "Dog", name: "Dog", qualifiedName: "Dog", kind: .class,
                    accessLevel: .public,
                    location: SourceLocation(filePath: "Sources/A/Dog.swift", line: 1, column: 1)
                )
            ],
            relationships: [Relationship(kind: .inheritance, source: "Dog", target: "Animal")]
        )
    }

    @Test func buildsNodesAndEdges() {
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: .init())
        #expect(model.nodes.count == 2)
        #expect(model.edges.count == 1)
        #expect(model.edges.first?.kind == .inheritance)
    }

    @Test func relationshipsHiddenWhenDisabled() {
        var config = ClassDiagramConfiguration()
        config.showRelationships = false
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: config)
        #expect(model.edges.isEmpty)
    }

    @Test func layoutAssignsAPositionToEveryNode() {
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: .init())
        let sizes = Dictionary(
            uniqueKeysWithValues: model.nodes.map { ($0.id, DiagramLayoutModel.estimateSize(for: $0)) }
        )
        let positions = model.performLayout(sizes: sizes)
        #expect(positions.count == model.nodes.count)
        for node in model.nodes {
            #expect(positions[node.id] != nil)
        }
    }

    @Test func estimateSizeIsPositive() {
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: .init())
        for node in model.nodes {
            let size = DiagramLayoutModel.estimateSize(for: node)
            #expect(size.width > 0)
            #expect(size.height > 0)
        }
    }

    @Test func directoryGroupingProducesBoxes() {
        var config = ClassDiagramConfiguration()
        config.grouping = .directory
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: config)
        let sizes = Dictionary(
            uniqueKeysWithValues: model.nodes.map { ($0.id, DiagramLayoutModel.estimateSize(for: $0)) }
        )
        let positions = model.performLayout(sizes: sizes)
        let boxes = model.groupingBoxes(positions: positions, sizes: sizes)
        #expect(!boxes.isEmpty)
    }

    @Test func noGroupingProducesNoBoxes() {
        var config = ClassDiagramConfiguration()
        config.grouping = .none
        let model = DiagramLayoutModel(artifact: sampleArtifact(), configuration: config)
        let boxes = model.groupingBoxes(positions: [:], sizes: [:])
        #expect(boxes.isEmpty)
    }
}
