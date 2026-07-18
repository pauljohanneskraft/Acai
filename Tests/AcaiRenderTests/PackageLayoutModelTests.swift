import CoreGraphics
import Testing
@testable import AcaiRender
@testable import AcaiDiagram

@Suite("Package Layout Model")
struct PackageLayoutModelTests {

    private func diagram() -> PackageDiagram {
        PackageDiagram(
            title: "Modules",
            nodes: [
                .init(id: "Core", name: "Core", typeCount: 10,
                      afferentCoupling: 3, efferentCoupling: 0, instability: 0, abstractness: 0.5),
                .init(id: "Feature", name: "Feature", typeCount: 5,
                      afferentCoupling: 0, efferentCoupling: 2, instability: 1, abstractness: 0),
                .init(id: "Util", name: "Util", typeCount: 2,
                      afferentCoupling: 1, efferentCoupling: 1, instability: 0.5, abstractness: 0)
            ],
            edges: [
                .init(from: "Feature", to: "Core", weight: 4),
                .init(from: "Feature", to: "Util", weight: 1),
                .init(from: "Util", to: "Core", weight: 2)
            ]
        )
    }

    @Test func allModulesGetNonOverlappingFrames() {
        let layout = PackageLayoutModel(diagram: diagram())
        #expect(layout.nodes.count == 3)
        for (index, a) in layout.nodes.enumerated() {
            #expect(a.rect.width > 0 && a.rect.height > 0)
            for b in layout.nodes[(index + 1)...] {
                #expect(!a.rect.intersects(b.rect), "\(a.id) overlaps \(b.id)")
            }
        }
    }

    @Test func dependedUponModuleRisesToTopLayer() {
        let layout = PackageLayoutModel(diagram: diagram())
        // `Core` is the dependency target of everything, so it lands in the top layer.
        let core = layout.frame(for: "Core")!
        for node in layout.nodes {
            #expect(core.midY <= node.rect.midY + 0.001)
        }
    }

    @Test func contentSizeCoversAllNodes() {
        let layout = PackageLayoutModel(diagram: diagram())
        #expect(layout.contentSize.width > 0)
        #expect(layout.contentSize.height > 0)
        for node in layout.nodes {
            #expect(node.rect.maxX <= layout.contentSize.width + 0.001)
            #expect(node.rect.maxY <= layout.contentSize.height + 0.001)
            #expect(node.rect.minX >= -0.001)
            #expect(node.rect.minY >= -0.001)
        }
    }

    @Test func edgesCarryWeights() {
        let layout = PackageLayoutModel(diagram: diagram())
        #expect(layout.edges.count == 3)
        #expect(layout.edges.contains { $0.from == "Feature" && $0.to == "Core" && $0.weight == 4 })
        #expect(layout.edges.contains { $0.from == "Util" && $0.to == "Core" && $0.weight == 2 })
    }

    @Test func positionOverridesAreStable() {
        let override = ["Util": CGPoint(x: 400, y: 300)]
        let first = PackageLayoutModel(diagram: diagram(), positionOverrides: override)
        let second = PackageLayoutModel(diagram: diagram(), positionOverrides: override)
        let frame = first.frame(for: "Util")!
        #expect(frame.width > 0)
        #expect(second.frame(for: "Util") == frame)
    }

    @Test func cyclicDependenciesDoNotHang() {
        let cyclic = PackageDiagram(
            nodes: [
                .init(id: "A", name: "A", typeCount: 1,
                      afferentCoupling: 1, efferentCoupling: 1, instability: 0.5, abstractness: 0),
                .init(id: "B", name: "B", typeCount: 1,
                      afferentCoupling: 1, efferentCoupling: 1, instability: 0.5, abstractness: 0)
            ],
            edges: [.init(from: "A", to: "B", weight: 1), .init(from: "B", to: "A", weight: 1)]
        )
        let layout = PackageLayoutModel(diagram: cyclic)
        #expect(layout.nodes.count == 2)
    }

    @Test func estimatedSizeGrowsWithNameLength() {
        let short = PackageLayoutModel.estimatedSize(
            for: .init(id: "A", name: "A", typeCount: 1, afferentCoupling: 0,
                       efferentCoupling: 0, instability: 0, abstractness: 0)
        )
        let long = PackageLayoutModel.estimatedSize(
            for: .init(id: "X", name: "AVeryLongModuleNameIndeed", typeCount: 1, afferentCoupling: 0,
                       efferentCoupling: 0, instability: 0, abstractness: 0)
        )
        #expect(long.width > short.width)
        #expect(short.height == long.height)
    }
}
