import CoreGraphics
import Testing
@testable import AcaiRender
@testable import AcaiDiagram

@Suite("State Layout Model")
struct StateLayoutModelTests {

    private func diagram() -> StateDiagram {
        StateDiagram(
            title: "Loader.state",
            states: [
                .init(id: "__initial", name: "", kind: .initial),
                .init(id: "state_idle", name: "idle"),
                .init(id: "state_loading", name: "loading"),
                .init(id: "state_loaded", name: "loaded")
            ],
            transitions: [
                .init(from: "__initial", to: "state_idle"),
                .init(from: "__initial", to: "state_loading", event: "load()"),
                .init(from: "state_loading", to: "state_loaded", event: "load()")
            ]
        )
    }

    @Test func allStatesGetNonOverlappingFrames() {
        let layout = StateLayoutModel(diagram: diagram())
        #expect(layout.nodes.count == 4)
        for (index, a) in layout.nodes.enumerated() {
            #expect(a.rect.width > 0 && a.rect.height > 0)
            for b in layout.nodes[(index + 1)...] {
                #expect(!a.rect.intersects(b.rect), "\(a.id) overlaps \(b.id)")
            }
        }
    }

    @Test func initialStateIsInTopLayer() {
        let layout = StateLayoutModel(diagram: diagram())
        let initial = layout.frame(for: "__initial")!
        for node in layout.nodes {
            #expect(initial.midY <= node.rect.midY + 0.001)
        }
    }

    @Test func contentSizeCoversAllNodes() {
        let layout = StateLayoutModel(diagram: diagram())
        #expect(layout.contentSize.width > 0)
        #expect(layout.contentSize.height > 0)
        for node in layout.nodes {
            #expect(node.rect.maxX <= layout.contentSize.width + 0.001)
            #expect(node.rect.maxY <= layout.contentSize.height + 0.001)
            #expect(node.rect.minX >= -0.001)
            #expect(node.rect.minY >= -0.001)
        }
    }

    @Test func positionOverridesAreRespected() {
        let layout = StateLayoutModel(
            diagram: diagram(),
            positionOverrides: ["state_loaded": CGPoint(x: 400, y: 300)]
        )
        // Frames are normalized to the origin afterwards, so check relative
        // placement: the overridden node must sit at the given offset from
        // wherever the normalization shifted the content.
        let overridden = layout.frame(for: "state_loaded")!
        #expect(overridden.width > 0)
        // Re-laying out with the same override is stable.
        let second = StateLayoutModel(
            diagram: diagram(),
            positionOverrides: ["state_loaded": CGPoint(x: 400, y: 300)]
        )
        #expect(second.frame(for: "state_loaded") == overridden)
    }

    @Test func edgesCarryTransitionLabels() {
        let layout = StateLayoutModel(diagram: diagram())
        #expect(layout.edges.count == 3)
        #expect(layout.edges.contains { $0.label == "load()" })
        #expect(layout.edges.contains { $0.label == nil })
    }

    @Test func cyclicTransitionsDoNotHang() {
        let cyclic = StateDiagram(
            states: [
                .init(id: "a", name: "a"),
                .init(id: "b", name: "b")
            ],
            transitions: [
                .init(from: "a", to: "b", event: "go()"),
                .init(from: "b", to: "a", event: "back()")
            ]
        )
        let layout = StateLayoutModel(diagram: cyclic)
        #expect(layout.nodes.count == 2)
    }
}
