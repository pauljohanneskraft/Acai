import Testing
import AcaiCore
@testable import AcaiDiff

@Suite("Diff: DeltaStatus badge mapping")
struct DeltaStatusTests {

    @Test func addedRemovedChangedHaveDistinctGlyphs() {
        #expect(DeltaStatus.added.badgeGlyph == "+")
        #expect(DeltaStatus.removed.badgeGlyph == "−")
        #expect(DeltaStatus.changed.badgeGlyph == "~")
    }

    @Test func unchangedHasNoBadge() {
        #expect(DeltaStatus.unchanged.badgeGlyph == nil)
        #expect(DeltaStatus.unchanged.badgeAccessibilityLabel == nil)
    }

    @Test func accessibilityLabelsAreHumanReadable() {
        #expect(DeltaStatus.added.badgeAccessibilityLabel == "Added")
        #expect(DeltaStatus.removed.badgeAccessibilityLabel == "Removed")
        #expect(DeltaStatus.changed.badgeAccessibilityLabel == "Changed")
    }

    @Test func everyBadgedStatusHasAColorToo() {
        for status in DeltaStatus.allCases where status.badgeGlyph != nil {
            #expect(status.deltaHex != nil)
        }
    }
}

@Suite("Diff: ArtifactDiff.typeChange(ofType:)")
struct ArtifactDiffTypeChangeAccessorTests {

    @Test func returnsTheFullChangeForAChangedType() {
        let change = TypeChange(id: "Widget", accessChange: Change(before: .internal, after: .public))
        let diff = ArtifactDiff(types: TypeDelta(added: [], removed: [], changed: [change]))
        let found = diff.typeChange(ofType: "Widget")
        #expect(found == change)
        #expect(diff.status(ofType: "Widget") == .changed)
    }

    @Test func returnsNilForAddedRemovedAndUnchangedTypes() {
        let diff = ArtifactDiff(types: TypeDelta(added: ["New"], removed: ["Gone"], changed: []))
        #expect(diff.typeChange(ofType: "New") == nil)
        #expect(diff.typeChange(ofType: "Gone") == nil)
        #expect(diff.typeChange(ofType: "NeverMentioned") == nil)
    }
}
