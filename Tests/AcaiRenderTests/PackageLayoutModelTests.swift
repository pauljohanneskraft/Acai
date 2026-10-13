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

    private func twoProjects() -> PackageDiagram {
        func node(_ project: String, _ module: String) -> PackageDiagram.Node {
            .init(id: "\(project)/\(module)", name: "\(project)/\(module)", project: project, typeCount: 1,
                  afferentCoupling: 0, efferentCoupling: 0, instability: 0, abstractness: 0)
        }
        return PackageDiagram(
            nodes: [node("alpha", "App"), node("alpha", "Core"), node("beta", "Core")],
            edges: [.init(from: "alpha/App", to: "alpha/Core", weight: 1)]
        )
    }

    @Test func projectBoxesStayInsideTheContent() {
        let layout = PackageLayoutModel(diagram: twoProjects())
        #expect(layout.projectBoxes.map(\.label) == ["alpha", "beta"])
        for box in layout.projectBoxes {
            #expect(box.rect.minX >= -0.001 && box.rect.minY >= -0.001, "\(box.id) starts off-canvas")
            #expect(box.rect.maxX <= layout.contentSize.width + 0.001)
            #expect(box.rect.maxY <= layout.contentSize.height + 0.001)
        }
    }

    @Test(arguments: [false, true])
    func aDraggedModuleLandsWhereItWasDropped(grouped: Bool) {
        let diagram = grouped ? twoProjects() : diagram()
        let initial = PackageLayoutModel(diagram: diagram)
        let anchor = initial.nodes.map(\.rect).min { ($0.minX, $0.minY) < ($1.minX, $1.minY) }!
        let moved = initial.nodes.first { $0.rect != anchor }!
        let drop = CGPoint(x: moved.rect.midX + 10, y: moved.rect.midY + 10)

        let relaid = PackageLayoutModel(diagram: diagram, positionOverrides: [moved.id: drop])
        let frame = relaid.frame(for: moved.id)!
        #expect(abs(frame.midX - drop.x) < 0.001 && abs(frame.midY - drop.y) < 0.001)
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
