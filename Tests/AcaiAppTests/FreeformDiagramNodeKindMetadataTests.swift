import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// Guards the consolidation from issue #123: `FreeformDiagramNodeKind`'s catalogue facts
/// (id/displayName/systemImage/catalogGroup) come from one exhaustive switch, and
/// `Content.canvasBehavior` replaces the `default:`-based `isResizable`/free-node checks that used
/// to let a new shape silently opt into "not resizable, not a free node."
@Suite("FreeformDiagramNodeKind metadata")
struct FreeformDiagramNodeKindMetadataTests {

    @Test("Every catalog entry has a unique id")
    func uniqueIDs() {
        let ids = FreeformDiagramNodeKind.allCases.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("Every catalog entry has a non-empty display name and icon")
    func nonEmptyDisplayFacts() {
        for kind in FreeformDiagramNodeKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test("Every catalog entry belongs to the group it's filed under")
    func catalogGroupRoundTrips() {
        for group in FreeformDiagramNodeKind.CatalogGroup.allCases {
            for kind in FreeformDiagramNodeKind.cases(in: group) {
                #expect(kind.catalogGroup == group)
            }
        }
    }

    @Test("Package/boundary/subsystem are resizable free nodes")
    func resizableContainers() {
        for content in [FreeformDiagram.Node.Content.package, .boundary, .subsystem] {
            let behavior = content.canvasBehavior
            #expect(behavior.isResizable)
            #expect(behavior.rendersAsFreeNode)
        }
    }

    @Test("Lifelines and fragments render through the sequence layer, not as free nodes")
    func sequenceLayerContent() {
        for content in [FreeformDiagram.Node.Content.lifeline(.object), .fragment(.init())] {
            let behavior = content.canvasBehavior
            #expect(!behavior.isResizable)
            #expect(!behavior.rendersAsFreeNode)
        }
    }

    @Test("Ordinary shapes render as fixed-size free nodes")
    func ordinaryFreeNodes() {
        let content = FreeformDiagram.Node.Content.actor
        let behavior = content.canvasBehavior
        #expect(!behavior.isResizable)
        #expect(behavior.rendersAsFreeNode)
    }

    @Test("Node.isResizable delegates to Content.canvasBehavior")
    func nodeIsResizableDelegates() {
        let node = FreeformDiagram.Node(name: "P", content: .package)
        #expect(node.isResizable)

        let other = FreeformDiagram.Node(name: "A", content: .actor)
        #expect(!other.isResizable)
    }
}
