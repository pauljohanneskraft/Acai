import Testing
@testable import AcaiApp

/// Chart-data-from-metrics coverage for the churn × complexity join and quadrant thresholds.
/// Uses the low-level `complexityByFile`/`churnByFile` initializer directly — no artifact or git
/// fixture needed, so the join/threshold logic is tested in isolation from both.
@Suite("Hotspot Chart Data")
struct HotspotChartDataTests {

    @Test("A file above both medians is a hotspot")
    func aboveBothMediansIsHotspot() {
        let data = HotspotChartData(
            complexityByFile: ["Hot.swift": 40, "Cold.swift": 2, "Mid.swift": 10],
            churnByFile: ["Hot.swift": 20, "Cold.swift": 1, "Mid.swift": 5]
        )
        let hot = data.points.first { $0.id == "Hot.swift" }
        #expect(hot?.isHotspot == true)
    }

    @Test("A file below either median is not a hotspot")
    func belowEitherMedianIsNotHotspot() {
        let data = HotspotChartData(
            complexityByFile: ["Hot.swift": 40, "Cold.swift": 2, "Mid.swift": 10],
            churnByFile: ["Hot.swift": 20, "Cold.swift": 1, "Mid.swift": 5]
        )
        let cold = data.points.first { $0.id == "Cold.swift" }
        #expect(cold?.isHotspot == false)
    }

    @Test("hotspots contains only top-right-quadrant files, ranked by churn × complexity")
    func hotspotsRankedByProduct() {
        let data = HotspotChartData(
            complexityByFile: ["A.swift": 30, "B.swift": 50, "C.swift": 1],
            churnByFile: ["A.swift": 10, "B.swift": 20, "C.swift": 1]
        )
        // Medians: complexity [1, 30, 50] -> 30; churn [1, 10, 20] -> 10 — only B.swift clears both.
        #expect(data.hotspots.map(\.id) == ["B.swift"])
    }

    @Test("A file present in only one map still produces a point, with the other value defaulting to 0")
    func missingFromOneMapDefaultsToZero() {
        let data = HotspotChartData(complexityByFile: ["OnlyComplexity.swift": 15], churnByFile: [:])
        let point = data.points.first { $0.id == "OnlyComplexity.swift" }
        #expect(point?.complexity == 15)
        #expect(point?.churn == 0)
    }

    @Test("Empty input produces no points")
    func emptyInputProducesNoPoints() {
        let data = HotspotChartData(complexityByFile: [:], churnByFile: [:])
        #expect(data.points.isEmpty)
        #expect(data.hotspots.isEmpty)
    }

    @Test("median of an even-count array averages the two middle values")
    func medianOfEvenCountAverages() {
        #expect([1.0, 2.0, 3.0, 4.0].median == 2.5)
    }

    @Test("median of an odd-count array is the middle value")
    func medianOfOddCountIsMiddle() {
        #expect([5.0, 1.0, 3.0].median == 3.0)
    }

    @Test("median of an empty array is 0")
    func medianOfEmptyArrayIsZero() {
        #expect([Double]().median == 0)
    }
}
