import Testing
@testable import AcaiApp

@Suite("String.shortName")
struct StringShortNameTests {
    @Test func returnsTheLastDotSeparatedComponent() {
        #expect("Foo.Bar.Baz".shortName == "Baz")
    }

    @Test func returnsTheWholeStringWhenThereIsNoDot() {
        #expect("Baz".shortName == "Baz")
    }
}
