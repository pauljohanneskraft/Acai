import Testing
@testable import AcaiQuality

@Suite("Hotspots")
struct HotspotsTests {

    @Test("Each file carries the type that sets its complexity, nil when it has none")
    func typeIsCarriedPerFile() {
        let hotspots = Hotspots(
            complexityByFile: ["Hot.swift": 40],
            churnByFile: ["Hot.swift": 20, "Readme.md": 3],
            typeByFile: ["Hot.swift": "App.Hot"]
        )
        #expect(hotspots.files.first { $0.path == "Hot.swift" }?.type == "App.Hot")
        #expect(hotspots.files.first { $0.path == "Readme.md" }?.type == nil)
    }

    @Test("A report limited by top still counts every hotspot")
    func reportTopKeepsFullCount() {
        let hotspots = Hotspots(
            complexityByFile: ["A.swift": 30, "B.swift": 50, "C.swift": 1, "D.swift": 1, "E.swift": 40],
            churnByFile: ["A.swift": 10, "B.swift": 20, "C.swift": 1, "D.swift": 1, "E.swift": 30]
        )
        let report = Hotspots.Report(hotspots: hotspots, commitWindow: 50, top: 1)
        #expect(report.hotspotCount == 2)
        #expect(report.hotspots.map(\.path) == ["E.swift"])
        #expect(report.filesScored == 5)
    }

    @Test("A file above both medians is a hotspot")
    func aboveBothMediansIsHotspot() {
        let hotspots = Hotspots(
            complexityByFile: ["Hot.swift": 40, "Cold.swift": 2, "Mid.swift": 10],
            churnByFile: ["Hot.swift": 20, "Cold.swift": 1, "Mid.swift": 5]
        )
        #expect(hotspots.files.first { $0.path == "Hot.swift" }?.isHotspot == true)
    }

    @Test("A file below either median is not a hotspot")
    func belowEitherMedianIsNotHotspot() {
        let hotspots = Hotspots(
            complexityByFile: ["Hot.swift": 40, "Cold.swift": 2, "Mid.swift": 10],
            churnByFile: ["Hot.swift": 20, "Cold.swift": 1, "Mid.swift": 5]
        )
        #expect(hotspots.files.first { $0.path == "Cold.swift" }?.isHotspot == false)
    }

    @Test("ranked contains only top-right-quadrant files, ordered by churn × complexity")
    func rankedByScore() {
        let hotspots = Hotspots(
            complexityByFile: ["A.swift": 30, "B.swift": 50, "C.swift": 1],
            churnByFile: ["A.swift": 10, "B.swift": 20, "C.swift": 1]
        )
        // Medians: complexity [1, 30, 50] -> 30; churn [1, 10, 20] -> 10 — only B.swift clears both.
        #expect(hotspots.ranked.map(\.path) == ["B.swift"])
    }

    @Test("Equal scores rank by path, so the report is reproducible")
    func equalScoresRankByPath() {
        let hotspots = Hotspots(
            complexityByFile: ["b.swift": 4, "a.swift": 2, "low.swift": 1, "none.swift": 1],
            churnByFile: ["b.swift": 2, "a.swift": 4, "low.swift": 1, "none.swift": 1]
        )
        #expect(hotspots.ranked.map(\.path) == ["a.swift", "b.swift"])
        #expect(hotspots.ranked.map(\.score) == [8, 8])
    }

    @Test("score is churn × complexity")
    func scoreIsProduct() {
        let hotspots = Hotspots(complexityByFile: ["A.swift": 7], churnByFile: ["A.swift": 3])
        #expect(hotspots.files.first?.score == 21)
    }

    @Test("A file present in only one map still produces an entry, the other value defaulting to 0")
    func missingFromOneMapDefaultsToZero() {
        let hotspots = Hotspots(complexityByFile: ["OnlyComplexity.swift": 15], churnByFile: [:])
        let file = hotspots.files.first { $0.path == "OnlyComplexity.swift" }
        #expect(file?.complexity == 15)
        #expect(file?.churn == 0)
    }

    @Test("fileName is the last path component")
    func fileNameIsLastComponent() {
        let hotspots = Hotspots(complexityByFile: ["Sources/App/Deep.swift": 1], churnByFile: [:])
        #expect(hotspots.files.first?.fileName == "Deep.swift")
    }

    @Test("Empty input produces no files")
    func emptyInputProducesNoFiles() {
        let hotspots = Hotspots(complexityByFile: [:], churnByFile: [:])
        #expect(hotspots.files.isEmpty)
        #expect(hotspots.ranked.isEmpty)
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
