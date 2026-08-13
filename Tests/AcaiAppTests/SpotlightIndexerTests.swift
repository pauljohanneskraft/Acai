import CoreSpotlight
import Foundation
import Testing
@testable import AcaiApp

@Suite("SpotlightIndexer")
struct SpotlightIndexerTests {
    @Test func mapsEntryIdentityAndDisplayFieldsOntoTheSearchableItem() {
        let entry = QuickOpenEntry(
            id: "type:Widget", name: "Widget", kind: .type, subtitle: "Demo — Demo Codebase",
            projectID: UUID(), codebaseID: UUID(), reference: .type(id: "Widget")
        )
        let item = SpotlightIndexer().searchableItem(for: entry)

        #expect(item.uniqueIdentifier == "type:Widget")
        #expect(item.domainIdentifier == SpotlightIndexer.domainIdentifier)
        #expect(item.attributeSet.title == "Widget")
        #expect(item.attributeSet.contentDescription == "Demo — Demo Codebase")
    }

    @Test func everyEntryKindMapsToAStableUniqueIdentifier() {
        let projectID = UUID()
        let codebaseID = UUID()
        let entries: [QuickOpenEntry] = [
            .init(id: "project:\(projectID)", name: "Demo", kind: .project, subtitle: "Project", projectID: projectID),
            .init(
                id: "codebase:\(codebaseID)", name: "Demo Codebase", kind: .codebase, subtitle: "Demo",
                projectID: projectID, codebaseID: codebaseID
            )
        ]
        let indexer = SpotlightIndexer()
        let identifiers = entries.map { indexer.searchableItem(for: $0).uniqueIdentifier }

        #expect(identifiers == ["project:\(projectID)", "codebase:\(codebaseID)"])
    }
}
