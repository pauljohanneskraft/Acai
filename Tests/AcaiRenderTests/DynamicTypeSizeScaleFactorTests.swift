import Testing
import SwiftUI
@testable import AcaiRender

@Suite("Dynamic Type Scale Factor")
struct DynamicTypeSizeScaleFactorTests {
    @Test func largeIsTheUnscaledBaseline() {
        #expect(DynamicTypeSize.large.scaleFactor == 1)
    }

    @Test func everyLargerSizeScalesUpMonotonically() {
        let ordered: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]
        for (smaller, larger) in zip(ordered, ordered.dropFirst()) {
            #expect(smaller.scaleFactor < larger.scaleFactor)
        }
    }

    @Test func accessibilitySizesScaleUpSubstantially() {
        // The largest accessibility size should be well over double the default — small enough
        // growth here would defeat the point of forcing it for a "does layout hold?" journey.
        #expect(DynamicTypeSize.accessibility5.scaleFactor > 2)
    }
}
