import Testing
@testable import AcaiApp

@Suite("Sequence.sorted(byLocalizedName:)")
struct SequenceLocalizedNameTests {
    private struct Named {
        let value: String
    }

    @Test func sortsCaseInsensitivelyAscending() {
        let items = [Named(value: "banana"), Named(value: "Apple"), Named(value: "cherry")]
        #expect(items.sorted(byLocalizedName: \.value).map(\.value) == ["Apple", "banana", "cherry"])
    }
}
